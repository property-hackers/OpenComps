-- Comp search RPC surface.
--
-- PostgREST-style clients cannot put PostGIS in filter params, so spatial
-- comp search ships as database functions callable via POST /rpc/<name>
-- (and plain SELECT for SQL clients). Shared conventions:
--   * anchor on lat/long or a us_zips ZIP centroid (dataset must be loaded)
--   * radius_m in meters, results ordered nearest-first
--   * invalid anchors/arguments raise SQLSTATE 22023
--
-- NOTE: no BEGIN/COMMIT here — tinbase wraps migrations in a transaction and
-- the psql paths apply migrations with -1.

CREATE FUNCTION resolve_search_anchor(
    lat DOUBLE PRECISION, long DOUBLE PRECISION, zip TEXT
) RETURNS GEOGRAPHY
LANGUAGE plpgsql STABLE AS $$
DECLARE
    anchor GEOGRAPHY;
BEGIN
    IF zip IS NOT NULL THEN
        SELECT z.location INTO anchor FROM us_zips z
        WHERE z.zip = resolve_search_anchor.zip;
        IF anchor IS NULL THEN
            RAISE EXCEPTION
                'unknown ZIP "%" (is the us_zips reference dataset loaded?)',
                zip USING ERRCODE = '22023';
        END IF;
    ELSIF lat IS NOT NULL AND long IS NOT NULL THEN
        anchor := ST_SetSRID(ST_MakePoint(long, lat), 4326)::GEOGRAPHY;
    ELSE
        RAISE EXCEPTION 'provide lat/long coordinates or a zip'
            USING ERRCODE = '22023';
    END IF;
    RETURN anchor;
END;
$$;

CREATE FUNCTION nearby_sales(
    lat DOUBLE PRECISION DEFAULT NULL,
    long DOUBLE PRECISION DEFAULT NULL,
    zip TEXT DEFAULT NULL,
    radius_m DOUBLE PRECISION DEFAULT 5000
) RETURNS TABLE (
    sale_id UUID,
    property_id UUID,
    property_name TEXT,
    comp_type TEXT,
    sale_date DATE,
    currency CHAR(3),
    sale_price NUMERIC(14,2),
    price_per_area NUMERIC(10,2),
    price_per_unit NUMERIC(14,2),
    unit_count_at_sale INTEGER,
    cap_rate NUMERIC(5,2),
    sale_type sale_type,
    verification_status verification_status,
    dist_meters DOUBLE PRECISION
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    anchor GEOGRAPHY := resolve_search_anchor(lat, long, zip);
BEGIN
    RETURN QUERY
    SELECT ps.id, p.id, p.name, ct.code, ps.sale_date, ps.currency,
           ps.sale_price, ps.price_per_area, ps.price_per_unit,
           ps.unit_count_at_sale, ps.cap_rate, ps.sale_type,
           ps.verification_status,
           ST_Distance(p.location, anchor)
    FROM property_sales ps
    JOIN properties p ON p.id = ps.property_id
    LEFT JOIN comp_types ct ON ct.id = ps.comp_type_id
    WHERE p.location IS NOT NULL
      AND ST_DWithin(p.location, anchor, radius_m)
    ORDER BY p.location <-> anchor, ps.sale_date DESC;
END;
$$;

CREATE FUNCTION nearby_unit_rents(
    lat DOUBLE PRECISION DEFAULT NULL,
    long DOUBLE PRECISION DEFAULT NULL,
    zip TEXT DEFAULT NULL,
    radius_m DOUBLE PRECISION DEFAULT 5000
) RETURNS TABLE (
    rent_id UUID,
    property_id UUID,
    property_name TEXT,
    comp_type TEXT,
    unit_type TEXT,
    bedrooms INTEGER,
    bathrooms NUMERIC(4,1),
    currency CHAR(3),
    rate_amount NUMERIC(14,2),
    rate_period rent_period,
    rate_basis unit_rate_basis,
    rate_type rate_type,
    observed_on DATE,
    verification_status verification_status,
    dist_meters DOUBLE PRECISION
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    anchor GEOGRAPHY := resolve_search_anchor(lat, long, zip);
BEGIN
    RETURN QUERY
    SELECT r.id, p.id, p.name, ct.code, r.unit_type, r.bedrooms, r.bathrooms,
           r.currency, r.rate_amount, r.rate_period, r.rate_basis, r.rate_type,
           r.observed_on, r.verification_status,
           ST_Distance(p.location, anchor)
    FROM property_unit_rents r
    JOIN properties p ON p.id = r.property_id
    LEFT JOIN comp_types ct ON ct.id = r.comp_type_id
    WHERE p.location IS NOT NULL
      AND ST_DWithin(p.location, anchor, radius_m)
    ORDER BY p.location <-> anchor, r.observed_on DESC;
END;
$$;

-- Area conversion between the two base unit systems (sq ft <-> m2).
CREATE FUNCTION convert_area(val NUMERIC, from_units unit_system, to_units unit_system)
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN val IS NULL OR from_units = to_units THEN val
        WHEN from_units = 'metric' THEN val * 10.7639104167097
        ELSE val / 10.7639104167097
    END
$$;

-- Subject-anchored comp selection: anchors on the subject property's own
-- location and asset class (matched via the sale's comp_type), excludes the
-- subject's sales, and applies appraisal-style culling. `as_of` is the
-- valuation effective date: comps sold after it never appear, and
-- max_age_months counts back from it. Size filters work in the subject's
-- unit system (comps in the other system are converted); the size basis is
-- GLA for residential, rentable building area for commercial classes,
-- unit count for multifamily, and lot size for land. When a size or vintage
-- filter is active, comps missing that attribute are excluded rather than
-- silently passed.
CREATE FUNCTION comps_for_property(
    subject_property_id UUID,
    radius_m DOUBLE PRECISION DEFAULT 5000,
    max_age_months INTEGER DEFAULT 36,
    as_of DATE DEFAULT CURRENT_DATE,
    same_property_type BOOLEAN DEFAULT FALSE,
    size_tolerance_pct NUMERIC DEFAULT NULL,
    min_size NUMERIC DEFAULT NULL,
    max_size NUMERIC DEFAULT NULL,
    year_built_tolerance INTEGER DEFAULT NULL,
    sale_types sale_type[] DEFAULT ARRAY['arms_length']::sale_type[],
    verified_only BOOLEAN DEFAULT FALSE,
    max_results INTEGER DEFAULT 25
) RETURNS TABLE (
    sale_id UUID,
    property_id UUID,
    property_name TEXT,
    property_type TEXT,
    comp_type TEXT,
    sale_date DATE,
    currency CHAR(3),
    sale_price NUMERIC(14,2),
    price_per_area NUMERIC(10,2),
    price_per_unit NUMERIC(14,2),
    unit_count_at_sale INTEGER,
    cap_rate NUMERIC(5,2),
    sale_type sale_type,
    verification_status verification_status,
    comp_size NUMERIC,
    year_built INTEGER,
    dist_meters DOUBLE PRECISION
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    subj_location GEOGRAPHY;
    subj_property_type_id UUID;
    subj_comp_type_id UUID;
    subj_comp_type_code TEXT;
    subj_size NUMERIC;
    subj_units unit_system;
    subj_year INTEGER;
    size_lo NUMERIC;
    size_hi NUMERIC;
    has_size_filter BOOLEAN :=
        size_tolerance_pct IS NOT NULL OR min_size IS NOT NULL OR max_size IS NOT NULL;
BEGIN
    SELECT p.location, p.property_type_id
    INTO subj_location, subj_property_type_id
    FROM properties p WHERE p.id = subject_property_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'unknown property %', subject_property_id
            USING ERRCODE = '22023';
    END IF;
    IF subj_location IS NULL THEN
        RAISE EXCEPTION 'property % has no location to search around',
            subject_property_id USING ERRCODE = '22023';
    END IF;
    IF subj_property_type_id IS NULL THEN
        RAISE EXCEPTION
            'property % has no property type, so no asset class to match comps on',
            subject_property_id USING ERRCODE = '22023';
    END IF;

    SELECT ct.id, ct.code INTO subj_comp_type_id, subj_comp_type_code
    FROM property_types pt
    JOIN comp_types ct ON ct.id = pt.comp_type_id
    WHERE pt.id = subj_property_type_id;

    -- subject size (in the subject's own units), unit system, and vintage
    SELECT
        CASE subj_comp_type_code
            WHEN 'residential' THEN rd.gla::NUMERIC
            WHEN 'multifamily' THEN COALESCE(
                cd.unit_count,
                (SELECT s.unit_count_at_sale FROM property_sales s
                 WHERE s.property_id = subject_property_id
                   AND s.unit_count_at_sale IS NOT NULL
                 ORDER BY s.sale_date DESC LIMIT 1))::NUMERIC
            WHEN 'land' THEN ld.lot_size
            ELSE cd.rentable_building_area
        END,
        COALESCE(CASE subj_comp_type_code
            WHEN 'residential' THEN rd.unit_system
            WHEN 'land' THEN ld.unit_system
            ELSE cd.unit_system
        END, 'imperial'),
        CASE subj_comp_type_code
            WHEN 'residential' THEN rd.year_built
            WHEN 'land' THEN NULL
            ELSE cd.year_built
        END
    INTO subj_size, subj_units, subj_year
    FROM (SELECT 1) AS one
    LEFT JOIN residential_details rd ON rd.property_id = subject_property_id
    LEFT JOIN commercial_details cd ON cd.property_id = subject_property_id
    LEFT JOIN land_details ld ON ld.property_id = subject_property_id;

    IF size_tolerance_pct IS NOT NULL THEN
        IF subj_size IS NULL THEN
            RAISE EXCEPTION
                'size_tolerance_pct set but the size of property % is unknown; use min_size/max_size instead',
                subject_property_id USING ERRCODE = '22023';
        END IF;
        size_lo := subj_size * (1 - size_tolerance_pct / 100);
        size_hi := subj_size * (1 + size_tolerance_pct / 100);
    END IF;
    size_lo := GREATEST(COALESCE(size_lo, min_size), COALESCE(min_size, size_lo));
    size_hi := LEAST(COALESCE(size_hi, max_size), COALESCE(max_size, size_hi));
    IF year_built_tolerance IS NOT NULL AND subj_year IS NULL THEN
        RAISE EXCEPTION
            'year_built_tolerance set but the year built of property % is unknown',
            subject_property_id USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT ps.id, p.id, p.name, pt.code, ct.code, ps.sale_date, ps.currency,
           ps.sale_price, ps.price_per_area, ps.price_per_unit,
           ps.unit_count_at_sale, ps.cap_rate, ps.sale_type,
           ps.verification_status,
           sz.comp_size, sz.comp_year, ST_Distance(p.location, subj_location)
    FROM property_sales ps
    JOIN properties p ON p.id = ps.property_id
    LEFT JOIN property_types pt ON pt.id = p.property_type_id
    LEFT JOIN comp_types ct ON ct.id = ps.comp_type_id
    LEFT JOIN LATERAL (
        SELECT
            CASE subj_comp_type_code
                WHEN 'residential' THEN
                    convert_area(rd.gla::NUMERIC, rd.unit_system, subj_units)
                WHEN 'multifamily' THEN
                    COALESCE(ps.unit_count_at_sale, cd.unit_count)::NUMERIC
                WHEN 'land' THEN
                    convert_area(ld.lot_size, ld.unit_system, subj_units)
                ELSE
                    convert_area(cd.rentable_building_area, cd.unit_system, subj_units)
            END AS comp_size,
            CASE subj_comp_type_code
                WHEN 'residential' THEN rd.year_built
                WHEN 'land' THEN NULL
                ELSE cd.year_built
            END AS comp_year
        FROM (SELECT 1) AS one
        LEFT JOIN residential_details rd ON rd.property_id = p.id
        LEFT JOIN commercial_details cd ON cd.property_id = p.id
        LEFT JOIN land_details ld ON ld.property_id = p.id
    ) sz ON TRUE
    WHERE ps.property_id <> subject_property_id
      AND ps.comp_type_id = subj_comp_type_id
      AND ps.sale_type = ANY (sale_types)
      AND ps.sale_date <= as_of
      AND (max_age_months IS NULL
           OR ps.sale_date >= as_of - make_interval(months => max_age_months))
      AND p.location IS NOT NULL
      AND ST_DWithin(p.location, subj_location, radius_m)
      AND (NOT same_property_type
           OR p.property_type_id = subj_property_type_id)
      AND (NOT verified_only OR ps.verification_status = 'verified')
      AND (NOT has_size_filter
           OR (sz.comp_size IS NOT NULL
               AND (size_lo IS NULL OR sz.comp_size >= size_lo)
               AND (size_hi IS NULL OR sz.comp_size <= size_hi)))
      AND (year_built_tolerance IS NULL
           OR (sz.comp_year IS NOT NULL
               AND ABS(sz.comp_year - subj_year) <= year_built_tolerance))
    ORDER BY p.location <-> subj_location, ps.sale_date DESC
    LIMIT max_results;
END;
$$;
