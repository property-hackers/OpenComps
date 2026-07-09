-- comps_for_property: subject-anchored comp selection. Anchors on the
-- subject's location, matches the subject's asset class via the SALE's
-- comp_type, excludes the subject's own sales, and applies appraisal-style
-- culling filters (recency window against an effective date, sale-type gate,
-- size bracket with unit-system normalization, vintage bracket).
-- Bad arguments raise SQLSTATE 22023.
\set ON_ERROR_STOP true

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;
\ir fixtures/atlanta_records.psql
\ir fixtures/comp_scenarios.psql

SELECT plan(15);

SELECT has_function('public', 'comps_for_property', 'comps_for_property RPC function exists');

-- ---------------------------------------------------------------------------
-- Scenario rows.
-- Subject: 276 Springdale Drive NE (RES_SFD, GLA 2,860 sq ft imperial,
-- built 1938, own sale f0...0001). Existing candidates: the condo sale
-- f0...0006 (~0.9 km, on an MF_MID-typed building, no residential_details)
-- and the 10 km bungalow. Added here: a metric-unit comp ~460 m away and an
-- REO sale on the condo.
-- ---------------------------------------------------------------------------
INSERT INTO properties (id, name, property_type_id, location)
SELECT '93000000-0000-0000-0000-000000000011', 'Metric Craftsman',
       '31000000-0000-0000-0000-000000000001',
       ST_SetSRID(ST_MakePoint(ST_X(location::GEOMETRY) + 0.005,
                               ST_Y(location::GEOMETRY)), 4326)::GEOGRAPHY
FROM properties WHERE id = '60000000-0000-0000-0000-000000000001';

INSERT INTO residential_details (property_id, unit_system, gla, year_built)
VALUES ('93000000-0000-0000-0000-000000000011', 'metric', 266, 1930);

INSERT INTO property_sales (
    id, property_id, comp_type_id, sale_date, sale_price, sale_type,
    unit_system, verification_status
)
VALUES (
    '93000000-0000-0000-0000-000000000021',
    '93000000-0000-0000-0000-000000000011',
    '30000000-0000-0000-0000-000000000001',
    '2025-10-01', 690000.00, 'arms_length', 'metric', 'unverified'
);

INSERT INTO property_sales (
    id, property_id, comp_type_id, sale_date, sale_price, sale_type,
    verification_status
)
VALUES (
    '93000000-0000-0000-0000-000000000022',
    '60000000-0000-0000-0000-000000000007',
    '30000000-0000-0000-0000-000000000001',
    '2024-11-01', 355000.00, 'reo', 'verified'
);

-- property with no property_type: no asset class to search on
INSERT INTO properties (id, name, location)
VALUES ('93000000-0000-0000-0000-000000000012', 'Untyped Property',
        ST_SetSRID(ST_MakePoint(-84.38, 33.83), 4326)::GEOGRAPHY);

-- ---------------------------------------------------------------------------
-- Baseline: same asset class, arms-length only, 36-month window, subject's
-- own sale excluded, 10 km bungalow outside the radius, REO gated out
-- ---------------------------------------------------------------------------
SELECT set_eq(
    $$
        SELECT sale_id FROM comps_for_property(
            '60000000-0000-0000-0000-000000000001',
            as_of => '2026-07-01')
    $$,
    ARRAY['f0000000-0000-0000-0000-000000000006',
          '93000000-0000-0000-0000-000000000021']::UUID[],
    'baseline pulls the condo and metric comps, excluding subject, REO, and out-of-radius'
);

SELECT set_eq(
    $$
        SELECT sale_id FROM comps_for_property(
            '60000000-0000-0000-0000-000000000001',
            as_of => '2026-07-01',
            sale_types => ARRAY['arms_length', 'reo']::sale_type[])
    $$,
    ARRAY['f0000000-0000-0000-0000-000000000006',
          '93000000-0000-0000-0000-000000000021',
          '93000000-0000-0000-0000-000000000022']::UUID[],
    'widening sale_types admits the REO sale'
);

SELECT set_eq(
    $$
        SELECT sale_id FROM comps_for_property(
            '60000000-0000-0000-0000-000000000001',
            as_of => '2026-07-01', max_age_months => 12)
    $$,
    ARRAY['93000000-0000-0000-0000-000000000021']::UUID[],
    'tighter recency window drops the 2024 condo sale'
);

-- retrospective valuation: comps after the effective date must not appear
SELECT set_eq(
    $$
        SELECT sale_id FROM comps_for_property(
            '60000000-0000-0000-0000-000000000001',
            as_of => '2024-09-01')
    $$,
    ARRAY['f0000000-0000-0000-0000-000000000006']::UUID[],
    'as_of excludes sales that happened after the effective date'
);

-- size bracket: subject GLA 2,860 sq ft; the metric comp (266 m2 = ~2,863
-- sq ft) converts into the bracket, the condo has no size and is culled
SELECT set_eq(
    $$
        SELECT sale_id FROM comps_for_property(
            '60000000-0000-0000-0000-000000000001',
            as_of => '2026-07-01', size_tolerance_pct => 10)
    $$,
    ARRAY['93000000-0000-0000-0000-000000000021']::UUID[],
    'size bracket normalizes metric comps and excludes comps with unknown size'
);

SELECT set_eq(
    $$
        SELECT sale_id FROM comps_for_property(
            '60000000-0000-0000-0000-000000000001',
            as_of => '2026-07-01', min_size => 2500)
    $$,
    ARRAY['93000000-0000-0000-0000-000000000021']::UUID[],
    'explicit min_size filters in the subject''s unit system'
);

SELECT set_eq(
    $$
        SELECT sale_id FROM comps_for_property(
            '60000000-0000-0000-0000-000000000001',
            as_of => '2026-07-01', verified_only => TRUE)
    $$,
    ARRAY['f0000000-0000-0000-0000-000000000006']::UUID[],
    'verified_only keeps only verified sales'
);

SELECT set_eq(
    $$
        SELECT sale_id FROM comps_for_property(
            '60000000-0000-0000-0000-000000000001',
            as_of => '2026-07-01', year_built_tolerance => 20)
    $$,
    ARRAY['93000000-0000-0000-0000-000000000021']::UUID[],
    'vintage bracket keeps the 1930 build and culls comps with unknown year built'
);

-- the condo sits on an MF_MID-typed building: strict property-type matching
-- drops it while comp-type matching kept it
SELECT set_eq(
    $$
        SELECT sale_id FROM comps_for_property(
            '60000000-0000-0000-0000-000000000001',
            as_of => '2026-07-01', same_property_type => TRUE)
    $$,
    ARRAY['93000000-0000-0000-0000-000000000021']::UUID[],
    'same_property_type narrows from asset class to exact property type'
);

SELECT results_eq(
    $$
        SELECT sale_id FROM comps_for_property(
            '60000000-0000-0000-0000-000000000001',
            as_of => '2026-07-01', max_results => 1)
    $$,
    $$
        VALUES ('93000000-0000-0000-0000-000000000021'::UUID)
    $$,
    'max_results keeps the nearest comp'
);

-- multifamily size basis: Emory Point has no commercial_details, so the
-- subject unit count falls back to its own sale's unit_count_at_sale
SELECT is(
    (
        SELECT COUNT(*) FROM comps_for_property(
            '60000000-0000-0000-0000-000000000004',
            as_of => '2026-07-01', size_tolerance_pct => 50)
    ),
    0::BIGINT,
    'multifamily subject resolves unit-count size from its sale without error'
);

SELECT throws_ok(
    $$ SELECT * FROM comps_for_property('99999999-0000-0000-0000-000000000000') $$,
    '22023',
    NULL,
    'unknown subject property raises invalid_parameter_value'
);

SELECT throws_ok(
    $$ SELECT * FROM comps_for_property('93000000-0000-0000-0000-000000000012') $$,
    '22023',
    NULL,
    'subject without a property type raises invalid_parameter_value'
);

-- condo subject: MF_MID -> multifamily basis, but no commercial_details and
-- no unit_count_at_sale on its sales -> size cannot be resolved
SELECT throws_ok(
    $$
        SELECT * FROM comps_for_property(
            '60000000-0000-0000-0000-000000000007',
            size_tolerance_pct => 10)
    $$,
    '22023',
    NULL,
    'size tolerance on a subject with unresolvable size raises invalid_parameter_value'
);

SELECT * FROM finish();

ROLLBACK;
