-- Comp-type metrics governance: canonical vocabulary ships with the schema,
-- and comp_types.field_definitions actually governs the `metrics` JSONB on
-- comp events. Enforcement is status-aware (mirrors the verified-only
-- ownership timeline constraint): unverified rows may carry messy keys,
-- pending_review/verified rows must conform. Violations raise SQLSTATE 23514.
--
-- Self-contained: no fixture include — the vocabulary assertions must hold on
-- a schema-only database.
\set ON_ERROR_STOP true

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(13);

-- ---------------------------------------------------------------------------
-- Canonical vocabulary exists after migration alone (no seed required)
-- ---------------------------------------------------------------------------
SELECT set_eq(
    'SELECT code FROM comp_types',
    ARRAY['residential', 'office', 'retail', 'multifamily', 'industrial',
          'land']::TEXT[],
    'canonical comp types ship with the schema'
);

SELECT set_eq(
    'SELECT code FROM property_types',
    ARRAY['RES_SFD', 'MF_MID', 'COM_OFF', 'COM_RET', 'COM_IND',
          'LND_COM']::TEXT[],
    'canonical property types ship with the schema'
);

SELECT is(
    (SELECT field_definitions #>> '{property_leases,rent_per_bed,type}'
     FROM comp_types WHERE code = 'residential'),
    'number',
    'residential field_definitions declare rent_per_bed for leases'
);

-- ---------------------------------------------------------------------------
-- Scenario rows the enforcement tests insert against
-- ---------------------------------------------------------------------------
INSERT INTO properties (id, name)
VALUES ('90000000-0000-0000-0000-000000000001', 'Governance Test Property');

-- ---------------------------------------------------------------------------
-- metrics must always be a JSON object, whatever the verification status
-- ---------------------------------------------------------------------------
SELECT throws_ok(
    $$
        INSERT INTO property_sales (property_id, sale_date, sale_type, metrics)
        VALUES ('90000000-0000-0000-0000-000000000001', '2024-01-15',
                'arms_length', '[]'::JSONB)
    $$,
    '23514',
    NULL,
    'metrics that are not a JSON object are rejected even when unverified'
);

-- ---------------------------------------------------------------------------
-- unverified rows tolerate messy keys (raw county imports)
-- ---------------------------------------------------------------------------
SELECT lives_ok(
    $$
        INSERT INTO property_sales (
            id, property_id, comp_type_id, sale_date, sale_type,
            metrics, verification_status
        )
        VALUES ('91000000-0000-0000-0000-000000000001',
                '90000000-0000-0000-0000-000000000001',
                (SELECT id FROM comp_types WHERE code = 'residential'),
                '2024-01-15', 'arms_length',
                '{"junk_from_import": "raw", "PRICE_PER_SQFT": "12x"}'::JSONB,
                'unverified')
    $$,
    'unverified sale may carry undefined metrics keys'
);

-- ...but they cannot be promoted to verified while still messy
SELECT throws_ok(
    $$
        UPDATE property_sales
        SET verification_status = 'verified'
        WHERE id = '91000000-0000-0000-0000-000000000001'
    $$,
    '23514',
    NULL,
    'promoting a sale with undefined metrics keys to verified fails'
);

-- ---------------------------------------------------------------------------
-- verified rows must conform to the comp type vocabulary
-- ---------------------------------------------------------------------------
SELECT throws_ok(
    $$
        INSERT INTO property_sales (
            property_id, comp_type_id, sale_date, sale_type,
            metrics, verification_status
        )
        VALUES ('90000000-0000-0000-0000-000000000001',
                (SELECT id FROM comp_types WHERE code = 'residential'),
                '2024-01-15', 'arms_length',
                '{"undefined_key": 1}'::JSONB, 'verified')
    $$,
    '23514',
    NULL,
    'verified sale with a metrics key missing from field_definitions fails'
);

SELECT throws_ok(
    $$
        INSERT INTO property_leases (
            property_id, comp_type_id, lease_type, transaction_type,
            commencement_date, rent_amount, rent_period,
            metrics, verification_status
        )
        VALUES ('90000000-0000-0000-0000-000000000001',
                (SELECT id FROM comp_types WHERE code = 'residential'),
                'residential', 'new_lease', '2024-06-01', 2400.00, 'monthly',
                '{"rent_per_bed": "eight hundred"}'::JSONB, 'verified')
    $$,
    '23514',
    NULL,
    'verified lease with a mistyped metrics value (string for number) fails'
);

SELECT throws_ok(
    $$
        INSERT INTO property_leases (
            property_id, comp_type_id, lease_type, transaction_type,
            commencement_date, rent_amount, rent_period,
            metrics, verification_status
        )
        VALUES ('90000000-0000-0000-0000-000000000001',
                (SELECT id FROM comp_types WHERE code = 'residential'),
                'residential', 'new_lease', '2024-06-01', 2400.00, 'monthly',
                '{"rent_per_bed": 800, "beds": 2.5}'::JSONB, 'verified')
    $$,
    '23514',
    NULL,
    'verified lease with a non-integral value for an integer field fails'
);

SELECT lives_ok(
    $$
        INSERT INTO property_leases (
            property_id, comp_type_id, lease_type, transaction_type,
            commencement_date, rent_amount, rent_period,
            metrics, verification_status
        )
        VALUES ('90000000-0000-0000-0000-000000000001',
                (SELECT id FROM comp_types WHERE code = 'residential'),
                'residential', 'new_lease', '2024-06-01', 2400.00, 'monthly',
                '{"rent_per_bed": 800, "beds": 3}'::JSONB, 'verified')
    $$,
    'verified lease with conforming metrics is accepted'
);

-- ---------------------------------------------------------------------------
-- comp types are an open set: a custom type can declare required fields
-- ---------------------------------------------------------------------------
INSERT INTO comp_types (id, code, name, primary_unit, field_definitions)
VALUES (
    '92000000-0000-0000-0000-000000000001', 'marina', 'Marina', 'slip',
    '{"property_sales": {
        "price_per_slip": {"type": "number", "unit": "currency_per_slip",
                           "label": "Price per slip", "required": true},
        "wet_slips": {"type": "integer", "unit": "count",
                      "label": "Wet slip count", "required": false}
    }}'::JSONB
);

SELECT throws_ok(
    $$
        INSERT INTO property_sales (
            property_id, comp_type_id, sale_date, sale_type,
            metrics, verification_status
        )
        VALUES ('90000000-0000-0000-0000-000000000001',
                '92000000-0000-0000-0000-000000000001',
                '2024-01-15', 'arms_length',
                '{"wet_slips": 120}'::JSONB, 'verified')
    $$,
    '23514',
    NULL,
    'verified sale missing a required metrics field fails'
);

SELECT lives_ok(
    $$
        INSERT INTO property_sales (
            property_id, comp_type_id, sale_date, sale_type,
            metrics, verification_status
        )
        VALUES ('90000000-0000-0000-0000-000000000001',
                '92000000-0000-0000-0000-000000000001',
                '2024-01-15', 'arms_length',
                '{"price_per_slip": 45000, "wet_slips": 120}'::JSONB,
                'verified')
    $$,
    'verified sale with all required metrics fields is accepted'
);

-- ---------------------------------------------------------------------------
-- no comp type claimed -> no vocabulary to enforce (object-ness still holds)
-- ---------------------------------------------------------------------------
SELECT lives_ok(
    $$
        INSERT INTO property_sales (
            property_id, sale_date, sale_type, metrics, verification_status
        )
        VALUES ('90000000-0000-0000-0000-000000000001', '2024-01-15',
                'arms_length', '{"anything": true}'::JSONB, 'verified')
    $$,
    'sale without a comp_type_id skips vocabulary validation'
);

SELECT * FROM finish();

ROLLBACK;
