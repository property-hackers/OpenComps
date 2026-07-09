\set ON_ERROR_STOP true

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;
\ir fixtures/atlanta_records.psql
\ir fixtures/comp_scenarios.psql
\ir fixtures/global_scenarios.psql

SELECT plan(12);

-- the core comp-search shape: residential sales within 5 km of the subject
SELECT set_eq(
    $$
        SELECT ps.id
        FROM property_sales ps
        JOIN properties p ON p.id = ps.property_id
        JOIN properties subject
          ON subject.id = '60000000-0000-0000-0000-000000000001'
        WHERE ps.comp_type_id = '30000000-0000-0000-0000-000000000001'
          AND p.id <> subject.id
          AND ST_DWithin(p.location, subject.location, 5000)
    $$,
    ARRAY['f0000000-0000-0000-0000-000000000006']::UUID[],
    'radius comp search finds the nearby condo sale and excludes the 10 km bungalow'
);

-- KNN ordering: nearest properties to the subject, closest first
SELECT results_eq(
    $$
        SELECT p.name::TEXT
        FROM properties p
        JOIN properties subject
          ON subject.id = '60000000-0000-0000-0000-000000000001'
        WHERE p.id <> subject.id
        ORDER BY p.location <-> subject.location
        LIMIT 3
    $$,
    $$
        VALUES
            ('2500 Peachtree Condominium'::TEXT),
            ('3324 Peachtree Office'::TEXT),
            ('Emory Point Apartments'::TEXT)
    $$,
    'nearest-neighbor ordering ranks candidate properties by distance'
);

-- jurisdiction boundary containment: which properties sit inside Fulton?
SELECT set_eq(
    $$
        SELECT p.name::TEXT
        FROM properties p
        JOIN jurisdictions j
          ON j.id = '40000000-0000-0000-0000-000000000001'
        WHERE ST_Contains(j.geom, p.location::GEOMETRY)
    $$,
    ARRAY[
        '276 Springdale Drive NE',
        '42 Atlanta Avenue SE',
        'Westpark Industrial Flex',
        '3324 Peachtree Office',
        '2500 Peachtree Condominium',
        'Fulton Industrial Blvd Land',
        'Roswell Road Assisted Living',
        'Downtown Atlanta Hotel'
    ]::TEXT[],
    'jurisdiction polygon containment separates Fulton properties from DeKalb and abroad'
);

-- the documented soft join: ZIP -> county jurisdiction via FIPS
SELECT is(
    (
        SELECT j.name
        FROM us_zips z
        JOIN jurisdictions j
          ON j.authority_code = z.county_fips
         AND j.kind = 'county'
         AND j.country = 'US'
        WHERE z.zip = '30305'
    ),
    'Fulton County',
    'ZIP joins to its county jurisdiction through the FIPS authority code'
);

-- geography distances come back in meters at real-world magnitudes
SELECT ok(
    (
        SELECT ST_Distance(a.location, b.location) BETWEEN 700 AND 1100
        FROM properties a, properties b
        WHERE a.id = '60000000-0000-0000-0000-000000000001'
          AND b.id = '60000000-0000-0000-0000-000000000007'
    ),
    'Springdale house and Peachtree condo are roughly 0.9 km apart'
);

-- ---------------------------------------------------------------------------
-- RPC comp search: the spatial surface PostgREST/MCP clients call
-- (POST /rpc/nearby_sales, /rpc/nearby_unit_rents)
-- ---------------------------------------------------------------------------
SELECT has_function('public', 'nearby_sales', 'nearby_sales RPC function exists');
SELECT has_function('public', 'nearby_unit_rents', 'nearby_unit_rents RPC function exists');

-- same shape as the raw radius search above, through the RPC surface
SELECT set_eq(
    $$
        SELECT sale_id
        FROM nearby_sales(
            lat => (SELECT ST_Y(location::GEOMETRY) FROM properties
                    WHERE id = '60000000-0000-0000-0000-000000000001'),
            long => (SELECT ST_X(location::GEOMETRY) FROM properties
                     WHERE id = '60000000-0000-0000-0000-000000000001'),
            radius_m => 5000)
        WHERE comp_type = 'residential'
    $$,
    ARRAY['f0000000-0000-0000-0000-000000000001',
          'f0000000-0000-0000-0000-000000000006']::UUID[],
    'nearby_sales finds the subject''s own sale and the nearby condo, not the 10 km bungalow'
);

-- ZIP-anchored search resolves the centroid through us_zips
SELECT ok(
    EXISTS (
        SELECT 1 FROM nearby_sales(zip => '30305', radius_m => 20000)
        WHERE sale_id = 'f0000000-0000-0000-0000-000000000006'
          AND dist_meters > 0
    ),
    'nearby_sales anchors on a ZIP centroid via us_zips'
);

SELECT ok(
    EXISTS (
        SELECT 1 FROM nearby_unit_rents(
            lat => (SELECT ST_Y(location::GEOMETRY) FROM properties
                    WHERE id = '60000000-0000-0000-0000-000000000012'),
            long => (SELECT ST_X(location::GEOMETRY) FROM properties
                     WHERE id = '60000000-0000-0000-0000-000000000012'),
            radius_m => 100)
        WHERE rent_id = 'f5000000-0000-0000-0000-000000000005'
    ),
    'nearby_unit_rents finds the hotel ADR observation at its own location'
);

SELECT throws_ok(
    'SELECT * FROM nearby_sales()',
    '22023',
    NULL,
    'nearby_sales without lat/long or zip raises invalid_parameter_value'
);

SELECT throws_ok(
    $$ SELECT * FROM nearby_sales(zip => '00000') $$,
    '22023',
    NULL,
    'nearby_sales with an unknown ZIP raises invalid_parameter_value'
);

SELECT * FROM finish();

ROLLBACK;
