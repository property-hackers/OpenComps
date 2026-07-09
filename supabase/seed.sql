-- ============================================================================
-- OpenComps dev seed: realistic Atlanta-metro dev data
-- Apply with scripts/seed_dev.sh (or: psql -f supabase/seed.sql
-- from anywhere -- the seed is self-contained).
--
-- Built from a curated sample of 250 real, public-record Atlanta-metro
-- addresses, inlined below as INSERTs. Everything else is
-- SYNTHETIC but deterministic: every random choice is hash-derived from the
-- address source_id, so reseeding always produces byte-identical data.
--
-- Requires: schema applied, us_zips loaded (counties come from the ZIP join).
-- ============================================================================
\set ON_ERROR_STOP true

BEGIN;

DO $guard$
BEGIN
    IF (SELECT COUNT(*) FROM us_zips) = 0 THEN
        RAISE EXCEPTION 'us_zips is empty -- run ./scripts/load_us_zips.sh first';
    END IF;
    IF EXISTS (SELECT 1 FROM data_providers WHERE code = 'dev_seed_bulk') THEN
        RAISE EXCEPTION 'dev seed already applied (provider dev_seed_bulk exists)';
    END IF;
END
$guard$;

-- deterministic pseudo-random in [0, 1), keyed on any text
CREATE FUNCTION pg_temp.hrand(key TEXT) RETURNS DOUBLE PRECISION
LANGUAGE SQL IMMUTABLE AS $$
    SELECT ((('x' || SUBSTR(MD5(key), 1, 8))::BIT(32)::INT::BIGINT & 2147483647))::DOUBLE PRECISION
           / 2147483647.0
$$;

-- deterministic UUID, keyed on a salt + id
CREATE FUNCTION pg_temp.duuid(salt TEXT, key TEXT) RETURNS UUID
LANGUAGE SQL IMMUTABLE AS $$
    SELECT MD5('opencomps-dev:' || salt || ':' || key)::UUID
$$;

-- ---------------------------------------------------------------------------
-- Staging: real addresses
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE _seed_addresses (
    source_id TEXT PRIMARY KEY,
    street_number TEXT, street_name TEXT, locality TEXT, region TEXT,
    postal_code TEXT, lon TEXT, lat TEXT  -- all-TEXT staging; NULLIF/cast at use
);

-- 250 curated Atlanta-metro addresses, inlined so the seed runs over any
-- connection (\copy is a psql meta-command and breaks the pglite socket).
INSERT INTO _seed_addresses VALUES
('00003fb4c4b4d290','1402','Huntcliff Village Court','Sandy Springs','GA','30350','-84.3515878','33.9991751'),
('000043627a0c56be','361','17th Street NW','Atlanta','GA','30363','-84.3980682','33.7916225'),
('0000f0b7f68e008a','1182','Grimes Bridge Road','Roswell','GA','30075','-84.342736','34.030437'),
('000109cb540ce023','125','Northwood Drive','Sandy Springs','GA','30342','-84.3828984','33.9087306'),
('00012fb6d3c3e2b9','3218','Saville Street SW','Atlanta','GA','30331','-84.5157922','33.6658156'),
('000142022a433413','625','Weeping Branch Court','Johns Creek','GA','30097','-84.1666202','34.0419774'),
('0001551ab571001a','7815','Carnegie Drive','South Fulton','GA','30213','-84.5698078','33.5439282'),
('00017aa0d7b4f390','126','Holcomb Ferry Road','Roswell','GA','30076','-84.3227696','34.0274411'),
('00017e9bb3c5e728','7628','Cozy Lane','South Fulton','GA','30213','-84.6370506','33.6086903'),
('00019ebfa5ba24a1','3668','Kingsboro Road NE','Atlanta','GA','30319','-84.3513341','33.8547141'),
('0001d0dfeae185b6','3553','Old Maple Drive','Johns Creek','GA','30022','-84.2565534','34.0249556'),
('0001f5e7cc1c46cb','125','Brindle Lane','Alpharetta','GA','30009','-84.2922063','34.0924032'),
('0001ff04c953eb2d','1807','Harbor Pointe Parkway','Sandy Springs','GA','30350','-84.3687338','33.9735701'),
('000251679c6031a4','1934','Markone Street NW','Atlanta','GA','30318','-84.4502659','33.7695487'),
('0003122eb803f564','2273','Collins Drive','East Point','GA','30344','-84.464797','33.6932911'),
('000341219095453a','1014','May''s Hill Street','South Fulton','GA','30331','-84.5655166','33.7273148'),
('00035128a5101f0b','973','Forrest Street','Roswell','GA','30075','-84.3570593','34.0252657'),
('0003746af68fd2db','5456','Cameron Parc Drive','Johns Creek','GA','30022','-84.2004336','34.0244888'),
('0003a03793802289','3564','Stone Road SW','Atlanta','GA','30331','-84.5053257','33.6769714'),
('0003b6a777176402','2030','Grant Road SW','Atlanta','GA','30331','-84.5190323','33.6992524'),
('000462e69b69c926','480','John Wesley Dobbs Avenue NE','Atlanta','GA','30312','-84.3708067','33.7595639'),
('0004a97f06b3650b','389','Inman Street SW','Atlanta','GA','30310','-84.4377585','33.7445682'),
('0004b6d82569e3d6','6339','Grey Fox Way','South Fulton','GA','30296','-84.461496','33.5839661'),
('0004de38407a9eab','19323','Deer Trail','Milton','GA','30004','-84.2532868','34.1001346'),
('0004febdc4c45a6b','3380','Old Alabama Road','Johns Creek','GA','30022','-84.2610088','34.0217287'),
('0005063b5603487b','4201','May Apple Lane','East Point','GA','30349','-84.5261095','33.6502747'),
('00052117b37cea9d','5805','Treelodge Parkway','Sandy Springs','GA','30350','-84.3566023','33.9661659'),
('00052eb025ce5ec2','5500','Riverwood Lane','Roswell','GA','30075','-84.3308489','34.022642'),
('000557cb9b7b1797','3453','Dacite Court','South Fulton','GA','30349','-84.5021734','33.5813054'),
('0005ae42e3165253','830','Loridan Circle NE','Atlanta','GA','30342','-84.3599831','33.8727686'),
('0005ce949dc897d0','707','Mayland Avenue SW','Atlanta','GA','30310','-84.4106891','33.7253674'),
('0005e0d56900a4d2','20','26th Street NW','Atlanta','GA','30309','-84.3939952','33.8020899'),
('0006031292590021','2602','Butner Road SW','Atlanta','GA','30331','-84.5322197','33.6839233'),
('000604e1f5b970ca','3633','Oakleaf Pass','South Fulton','GA','30213','-84.506593','33.5501311'),
('00064c660fa2e30a','2534','Bolton Road NW','Atlanta','GA','30318','-84.452174','33.8210626'),
('00065605d267bd35','2660','Peachtree Road NW','Atlanta','GA','30305','-84.3880371','33.8274751'),
('000683fd438f2d06','7918','Bluefin Trail','South Fulton','GA','30291','-84.5316521','33.5443517'),
('00068ff79d41c02c','12080','Wexford Club Drive','Roswell','GA','30075','-84.3762521','34.075018'),
('0006a5eb39ffceaa','3768','Shenfield Drive','South Fulton','GA','30291','-84.525409','33.5817829'),
('0006de14d9147b92','105','River Terrace Pointe','Roswell','GA','30076','-84.3069989','33.9980895'),
('00073c6b35071ca7','760','Bender Street SW','Atlanta','GA','30310','-84.4059827','33.7343648'),
('00075101f06ff412','8496','Hearn Road','Chattahoochee Hills','GA','30268','-84.7116385','33.5225793'),
('00076923f466634d','374','Noelle Ridge Drive SW','Atlanta','GA','30311','-84.474031','33.7447281'),
('00076e5d0c9cc15d','1915','Perry Boulevard NW','Atlanta','GA','30318','-84.4496036','33.7952582'),
('0007a853d2bed3f9','2980','Argonne Drive NW','Atlanta','GA','30305','-84.4065455','33.8363072'),
('0007aeb87d5701c8','1240','Birchwood Lane','Roswell','GA','30076','-84.3564266','34.074915'),
('0007fe0111e904a6','6031','Oak Bend Court','South Fulton','GA','30296','-84.466899','33.586828'),
('000856237470f06f','433','Belmont Drive','Roswell','GA','30022','-84.2809479','34.0036636'),
('00086a0eae6ba110','1196','Mayland Circle SW','Atlanta','GA','30310','-84.405586','33.722376'),
('0008b54e4c077b66','1333','Aniwaka Avenue SW','Atlanta','GA','30311','-84.4413799','33.7190916'),
('0008f4e4c1beb34f','485','Boulevard Place NE','Atlanta','GA','30308','-84.3713018','33.7697445'),
('0008f5f0d5ad45ea','5050','Buice Road','Johns Creek','GA','30022','-84.2148669','34.0179547'),
('00092ab692848c0a','1413','Rosemont Parkway','Roswell','GA','30076','-84.3217605','34.0576174'),
('0009babfb3d97eb6','1125','Spalding Drive','Sandy Springs','GA','30350','-84.3498071','33.9591688'),
('0009db67cf9942fe','870','Inman Village Parkway NE','Atlanta','GA','30307','-84.3605155','33.7613951'),
('000a097c2a880a6f','3852','Bonnie Lane SE','Atlanta','GA','30354','-84.3576241','33.649202'),
('000a61f64554ee9f','9009','Woodland Trail','Alpharetta','GA','30009','-84.2733007','34.0728091'),
('000a683eda59832e','435','Whispering Wind Lane','Roswell','GA','30022','-84.2865114','34.0105137'),
('000a98fc5f04cd94','1856','Delowe Place SW','Atlanta','GA','30311','-84.4585817','33.7043914'),
('000aec24558030b2','2415','Hemingway Lane','Roswell','GA','30075','-84.3310453','34.0179355'),
('000aff755c816c72','5476','Babbling View','South Fulton','GA','30213','-84.6394553','33.6075895'),
('000b0510b1d7a293','2310','Shancey Lane','South Fulton','GA','30349','-84.4654485','33.6045776'),
('000b512224c9672d','681','University Avenue SW','Atlanta','GA','30310','-84.4099819','33.7226817'),
('000b6a2bf3d2f4cd','12570','Arbor North Drive','Milton','GA','30004','-84.3492759','34.0881752'),
('000bb97c1cdd5844','742','Kirkwood Avenue SE','Atlanta','GA','30316','-84.3630169','33.7505135'),
('000bfd04be10f862','7323','Cardigan Circle','Sandy Springs','GA','30328','-84.372086','33.9476243'),
('000c0c3ad2511a26','839','Drummond Street SW','Atlanta','GA','30314','-84.4150421','33.7529855'),
('000c12c9131d818d','10235','Groomsbridge Road','Johns Creek','GA','30022','-84.1971687','34.0305743'),
('000c1ae8c7093c6e','13935','Sunfish Bend','Milton','GA','30004','-84.2617891','34.1214576'),
('000c4016c3398b87','2640','Fairburn Road SW','Atlanta','GA','30331','-84.513641','33.6813706'),
('000c4dd6804d3b51','4170','Sweet Water Parkway','ELLENWOOD','GA','30294','-84.2095116','33.6568534'),
('000c4ec454fa9ffa','11265','Easthaven Place','Johns Creek','GA','30097','-84.1642705','34.0545209'),
('000cb03adf9005d2','23317','Plantation Drive NE','Atlanta','GA','30324','-84.3570893','33.8367915'),
('000ccc6f902a08d0','1725','Leslie Avenue SW','Atlanta','GA','30311','-84.4444802','33.7076963'),
('000cf9294f673637','986','Old Powers Ferry Road','Sandy Springs','GA','30327','-84.4180459','33.9047828'),
('000d6b4060fed2b9','290','Hilderbrand Drive','Sandy Springs','GA','30328','-84.3777075','33.9235686'),
('000d7b3f383574b0','535','Twin Lakes Court','South Fulton','GA','30213','-84.6461584','33.6367863'),
('000d94cea4c0adcc','146','11th Street NE','Atlanta','GA','30308','-84.3824088','33.7786904'),
('000e08605975f77b','170','Wallace Road SW','Atlanta','GA','30354','-84.3953148','33.6675203'),
('000e1423f6ff21fa','633','Summer Crossing','Sandy Springs','GA','30350','-84.3347351','34.0014505'),
('000e81b684ad15b6','1006','Applegate Drive','Roswell','GA','30076','-84.3509439','34.0748738'),
('000e9f695a588bc2','330','Knoll Ridge Court','Alpharetta','GA','30022','-84.2717649','34.0353638'),
('000eed4c375f3434','869','Artistry Way','South Fulton','GA','30213','-84.6482231','33.6397654'),
('000f01d183f42ea1','747','Ralph Mcgill Boulevard NE','Atlanta','GA','30312','-84.3623867','33.7667023'),
('000f5a86169eedfa','1901','Sandalwood Drive','Sandy Springs','GA','30350','-84.3457291','33.9966802'),
('000f5d819bc9c446','3014','North Street','East Point','GA','30344','-84.4301791','33.6728842'),
('001000f6a913afe3','1495','Masters Club Drive','Sandy Springs','GA','30350','-84.320396','33.9733521'),
('00100d16c95e610f','1985','Cascade Road SW','Atlanta','GA','30311','-84.4527838','33.7220924'),
('00105c3770b064a4','1994','Donald Lee Hollowell Parkway NW','Atlanta','GA','30318','-84.4503717','33.7766321'),
('0010620888dab2d5','954','Joseph E Boone Boulevard NW','Atlanta','GA','30314','-84.4187904','33.7632281'),
('0010c72bc80018d0','1911','Seven Seas Court','Alpharetta','GA','30005','-84.2218645','34.0750744'),
('0011254adc169b6c','3740','Hampshire Walk SW','Atlanta','GA','30331','-84.5097401','33.6811791'),
('00112846567fcc25','4006','Wieuca Road NE','Atlanta','GA','30342','-84.3677174','33.862612'),
('00112f280ce2c1f2','3511','Glenview Circle SW','Atlanta','GA','30331','-84.503231','33.7040455'),
('00117e3724f6cdf4','409','River Mill Circle','Roswell','GA','30075','-84.3563618','34.0076663'),
('00118d36cf223a55','320','Maxwell Road','Alpharetta','GA','30009','-84.3010055','34.0671972'),
('0011a555e69383ca','2833','Overlook Trace NE','Atlanta','GA','30324','-84.358664','33.83275'),
('0011ac92ddf11bea','1034','Euclid Avenue NE','Atlanta','GA','30307','-84.3534001','33.7623657'),
('0011b4fb13a983a4','3650','Pebble Beach Drive','South Fulton','GA','30349','-84.5078938','33.5946758'),
('0011e2eab328e0eb','3069','Sable Run Road','South Fulton','GA','30349','-84.5056922','33.6004264'),
('0011ec8477603092','215','Semel Drive NW','Atlanta','GA','30309','-84.4004317','33.8028351'),
('001205323ea0fe49','4059','Ester Drive SW','Atlanta','GA','30331','-84.5203888','33.7541905'),
('001225f104070fdf','5920','Roswell Road','Sandy Springs','GA','30328','-84.3809007','33.9170748'),
('00124730aacfab05','1515','Liberty Lane','Roswell','GA','30075','-84.3540724','34.0286109'),
('00127ed856dabdd7','685','Mc Williams Road SE','Atlanta','GA','30315','-84.3664537','33.6885695'),
('0012a62bc6e6bdb3','770','Old Roswell Place','Roswell','GA','30076','-84.340181','34.0345787'),
('0012ab93115d4d28','543','Monticello Boulevard SE','Atlanta','GA','30354','-84.3804848','33.6655568'),
('0012c0bcd9b1e9f2','3593','Paces Valley Road NW','Atlanta','GA','30327','-84.4093096','33.8526184'),
('0012c70d8f249d3b','1090','Loring Street SE','Atlanta','GA','30316','-84.3516594','33.7376892'),
('0012cb366ecb73ed','6679','Mancha Street','South Fulton','GA','30349','-84.4678788','33.5726488'),
('001332448db97b26','3314','Sequoia Avenue','South Fulton','GA','30349','-84.5853722','33.6648475'),
('00136fedab9ef280','120','Clover Court','Roswell','GA','30075','-84.3560511','34.0213698'),
('0013f9f0c67cca88','8640','Niblick Drive','Johns Creek','GA','30022','-84.2634798','33.9893394'),
('00143426d1630b1c','371','Boulevard   NE','Atlanta','GA','30312','-84.3714647','33.7645579'),
('00143977e6616618','105','Elaine Drive','Roswell','GA','30075','-84.3435067','34.0260044'),
('001442c8293e0bc3','5051','Brookside Court','Alpharetta','GA','30004','-84.2785606','34.0863895'),
('00145dfeedb075f1','2782','Normandy Drive NW','Atlanta','GA','30305','-84.4030855','33.8307232'),
('0014e4e2c998a676','3651','Schooner Ridge','Alpharetta','GA','30005','-84.2207507','34.0763148'),
('0014f374936c0894','720','Abbeywood Drive','Roswell','GA','30075','-84.3959426','34.0233004'),
('0015078b61082490','205','Happy Hollow Court','South Fulton','GA','30349','-84.5361985','33.6334965'),
('00150c132b30477e','2800','Camp Creek Parkway','College Park','GA','30337','-84.4795934','33.650159'),
('0015142c7802856a','1074','Welch Street SW','Atlanta','GA','30310','-84.4046125','33.7255907'),
('00151b09d9e94302','420','Wexford Overlook Drive','Roswell','GA','30075','-84.3701459','34.0714275'),
('00156795a46cb407','4969','Roswell Road','Sandy Springs','GA','30342','-84.3806693','33.8898955'),
('0015888ad881320a','18','Scotland Place NW','Atlanta','GA','30318','-84.4415225','33.8236859'),
('001595502fa83403','366','Altoona Place SW','Atlanta','GA','30310','-84.4347647','33.7452143'),
('0015be47c323738e','3607','Tree Ridge Parkway','Roswell','GA','30022','-84.2763897','33.9918161'),
('0015e3a1aa496eeb','2325','Shancey Lane','South Fulton','GA','30349','-84.4658713','33.6049087'),
('00163d0d4318485c','988','Bouldercrest Drive SE','Atlanta/DeKalb','GA','30316','-84.3329432','33.7272834'),
('00163d5315658eda','1822','Dodson Drive SW','Atlanta','GA','30311','-84.4765384','33.705636'),
('00163dfd0ebd23c4','11067','Peachcove Court','Johns Creek','GA','30024','-84.1184655','34.0479204'),
('00165cc5f8a1efb3','918','Stream Valley Trail','Alpharetta','GA','30022','-84.2368188','34.0542199'),
('00167e36a7fc0855','5545','Woodside Drive   SW','South Fulton','GA','30331','-84.5698484','33.6976549'),
('0016b5b563b9bb8a','940','New Hope Road SW','Atlanta','GA','30331','-84.5393217','33.7285222'),
('0016cf64703c6876','1265','Heatherland Drive   SW','South Fulton','GA','30331','-84.539805','33.7200436'),
('0016d2dc6e215d69','2305','Hopewell Plantation Drive','Milton','GA','30004','-84.2915021','34.1074051'),
('0016eec5188c246d','10995','State Bridge Road','Johns Creek','GA','30022','-84.2252679','34.0499991'),
('00172dcde54288fe','874','Hollywood Road NW','Atlanta','GA','30318','-84.454616','33.7786769'),
('001736804650fc84','365','Findley Way','Johns Creek','GA','30097','-84.1833485','34.0647252'),
('00175517a9f0c1a5','404','Masons Creek Circle','Sandy Springs','GA','30350','-84.3404488','33.9925808'),
('00178e8aa850fda2','3248','Saville Street SW','Atlanta','GA','30331','-84.5167264','33.6643566'),
('0017d4ab771d66cc','2561','Red Valley Road NW','Atlanta','GA','30305','-84.401506','33.8248742'),
('0017e497e6b6b86e','400','Fairburn Road SW','Atlanta','GA','30331','-84.5077053','33.7425152'),
('0017e6de5e698ec1','199','14th Street NE','Atlanta','GA','30309','-84.3807966','33.7861408'),
('0017fbbe409fecf2','235','Gaitskell Lane','Johns Creek','GA','30022','-84.2087245','34.0301285'),
('001816847b2b9976','1753','Mary George Avenue NW','Atlanta','GA','30318','-84.4655167','33.8033428'),
('0018255274b06600','85','Mill Street','Roswell','GA','30075','-84.3597336','34.0139591'),
('00184999bb89bbb9','1238','Oak Grove Avenue SE','Atlanta/DeKalb','GA','30316','-84.347027','33.7430898'),
('001868a94b27b176','225','Taylor Meadow Chase','Roswell','GA','30076','-84.3311828','34.0672335'),
('00189dade9aeb3cd','923','Peachtree Street NE','Atlanta','GA','30309','-84.383459','33.780409'),
('0018e40a9d19769e','5492','Glenridge Drive','Sandy Springs','GA','30342','-84.3713736','33.9044279'),
('0018f0a2f3fe95c1','957','Samples Lane NW','Atlanta','GA','30318','-84.4492145','33.7912006'),
('0019700175a397a3','330','Chickering Lake Court','Roswell','GA','30075','-84.39566','34.0280116'),
('001981bb60886995','3958','Stonewall Tell Road','South Fulton','GA','30349','-84.5930418','33.6475067'),
('0019a561cffca805','555','Stonebrook Farms Drive','Milton','GA','30004','-84.2772522','34.1583793'),
('0019c1f6f6d6bdb5','2968','Grand Avenue SW','Atlanta','GA','30315','-84.4041568','33.6747282'),
('0019c8bd77b9ad17','1321','Sharon Street NW','Atlanta','GA','30314','-84.4307101','33.7548093'),
('001a0df650437b3e','1208','Deerfield Avenue','Milton','GA','30004','-84.2587157','34.0986012'),
('001a230be769229f','273','Linkwood Road NW','Atlanta','GA','30318','-84.4836719','33.762848'),
('001a86e9907f4386','650','Richmond Glen Drive','Milton','GA','30004','-84.3428224','34.1348955'),
('001a9a97172a176e','330','Thorndale Court','Roswell','GA','30075','-84.3945963','34.0245318'),
('001aa85edbeb85c3','400','Grant Circle SE','Atlanta','GA','30315','-84.3741382','33.7259743'),
('001acd623d6f634e','2392','Hyde Manor Drive NW','Atlanta','GA','30327','-84.4364363','33.8208712'),
('001b01686f423f93','1743','Madrona Street NW','Atlanta','GA','30318','-84.4441111','33.7708442'),
('001b05b702da5fce','3057','Pharr Court North   NW','Atlanta','GA','30305','-84.3834548','33.8384245'),
('001b1271f951c7c7','862','Lagoon Court','STONE MOUNTAIN','GA','30083','-84.232527','33.8025947'),
('001b2809e1724a18','13270','Owens Way','Milton','GA','30004','-84.3491652','34.1063424'),
('001b47d03441bd54','5819','Village Loop','South Fulton','GA','30213','-84.6388077','33.6094533'),
('001b7606168da3a3','705','Cameron Bridge Way','Johns Creek','GA','30022','-84.220955','34.0423473'),
('001b88998c0b3058','4020','Stovall Terrace NE','Atlanta','GA','30342','-84.3613718','33.8646651'),
('001ba1b9c5d5ac8a','3022','Park Street','East Point','GA','30344','-84.4472687','33.6729869'),
('001bb0a4a4c2366e','25','Oak Street','Roswell','GA','30075','-84.3607007','34.019453'),
('001bd45dc9540eac','7945','Lester Road','South Fulton','GA','30213','-84.5240089','33.5423392'),
('001bdb8c3505b896','2770','Crescendo Drive NW','Atlanta','GA','30318','-84.478172','33.7740566'),
('001bed34a9c21743','903','Brighton Point','Sandy Springs','GA','30328','-84.3661286','33.9574377'),
('001bfd7a21e71804','702','Oliver Street NW','Atlanta','GA','30318','-84.4157086','33.7739435'),
('001c14401b61984c','2726','3rd Avenue SW','Atlanta','GA','30315','-84.4022099','33.6805912'),
('001ccaf007fc2ac8','5100','Welcome All Road','South Fulton','GA','30349','-84.5243449','33.6143882'),
('001cd02cf5e549cb','1391','Mcclelland Avenue','East Point','GA','30344','-84.4344183','33.6987703'),
('001d2b30c3d9877e','1250','Old Woodbine Road','Sandy Springs','GA','30319','-84.3492972','33.8860909'),
('001d4ec13798e586','12615','Lighthouse Pointe Court','Alpharetta','GA','30005','-84.2104304','34.086603'),
('001d50d5328f95f4','418','Springberry Court','Alpharetta','GA','30005','-84.2410292','34.062938'),
('001d5d2745b504c7','2004','Bader Avenue SW','Atlanta','GA','30310','-84.4139418','33.6999063'),
('001d6923353cc0e4','1330','Millstone Drive','Alpharetta','GA','30004','-84.2818681','34.0886616'),
('001da5c21dc6e271','3481','Lakeside Drive NE','Atlanta','GA','30326','-84.3571439','33.8490826'),
('001dab01b0b8da49','1280','West  Peachtree Street NW','Atlanta','GA','30309','-84.3888045','33.7896852'),
('001dbf6875476d5c','142','Maple Street NW','Atlanta','GA','30314','-84.4056125','33.7584514'),
('001e1b52268f0f3c','848','Dolly Avenue   SW','South Fulton','GA','30331','-84.5657367','33.6933978'),
('001e28843c9aff4b','11203','Calypso Drive','Alpharetta','GA','30009','-84.3010144','34.0534492'),
('001e6c7ec39d0343','9995','Jones Bridge Road','Johns Creek','GA','30022','-84.2502614','34.0271503'),
('001ea07bf66645a2','999','North Avenue NW','Atlanta','GA','30318','-84.4202047','33.7691928'),
('001eaccb01f37a88','1201','West Lane NW','Atlanta','GA','30318','-84.4145044','33.7874124'),
('001eade5ca4c88d1','2657','Lenox Road NE','Atlanta','GA','30324','-84.3533805','33.8273196'),
('001f304c7f59a25f','2783','Blount Street','East Point','GA','30344','-84.4237528','33.6791696'),
('001f6014e8ce4cce','920','Charleston Court','Roswell','GA','30075','-84.3863514','34.0313304'),
('001fc954c49bf79f','12980','Old Course Drive','Roswell','GA','30075','-84.4164753','34.0989803'),
('001fec567681de9d','10592','Naramore Lane','Johns Creek','GA','30022','-84.2178847','34.03962'),
('001ffa70ad9892a7','3941','Makeover Court','South Fulton','GA','30349','-84.5191868','33.6057441'),
('001ffdb4b5bf9af7','8470','Ono Road','South Fulton','GA','30268','-84.6642938','33.5414854'),
('0020047f153f3380','1569','Glenwood Avenue SE','Atlanta/DeKalb','GA','30316','-84.3362446','33.739706'),
('002048794c475500','3210','Deer Trail','Milton','GA','30004','-84.2563083','34.1006703'),
('00204f50b60198dd','195','14th Street NE','Atlanta','GA','30309','-84.3810032','33.7857431'),
('00204fff510ec20a','9055','Terry Road','South Fulton','GA','30213','-84.6847144','33.5878043'),
('0020712a9895cdd3','11312','Musette Circle','Alpharetta','GA','30009','-84.3005647','34.0566318'),
('00207c9a2ff96db1','14','Waddell Street NE','Atlanta','GA','30307','-84.3628564','33.7538394'),
('0020969217db2a21','3208','Spring Creek Lane','Sandy Springs','GA','30350','-84.3657332','33.9732113'),
('0020ccb512f4fc57','165','Pine Street','AVONDALE ESTATES','GA','30002','-84.2728201','33.7776937'),
('00210e9036ca1971','416','Fayetteville Road','Fairburn','GA','30213','-84.5680164','33.5623459'),
('00216bc6d09086ba','715','Beaver Pond Trail','South Fulton','GA','30213','-84.620305','33.5747066'),
('0021f264edbbaa9b','215','Brassy Court','Johns Creek','GA','30022','-84.260944','33.9899437'),
('002220ceb6612e9d','1285','Shanter Trail SW','Atlanta','GA','30311','-84.5000515','33.7205357'),
('002236786c25c81a','66','Whitehouse Drive SW','Atlanta','GA','30314','-84.4195148','33.7530224'),
('00224219cd69aae7','3799','Boulder Park Drive SW','Atlanta','GA','30331','-84.5122472','33.748219'),
('00224f8c29f8fc21','100','Butler Creek Court','Johns Creek','GA','30097','-84.1705185','34.0319082'),
('0022a010e805e78a','430','Clear Creek Terrace','Roswell','GA','30076','-84.3098513','34.006898'),
('0022a46457ec41b8','1498','Martin L King Jr Drive SW','Atlanta','GA','30314','-84.4363891','33.7529647'),
('0022fde1a362d6ac','535','Parker Avenue SE','Atlanta/DeKalb','GA','30317','-84.3007347','33.7386508'),
('002324cf5cf8a4c9','2400','Riverwood Lane','Roswell','GA','30075','-84.3339691','34.0219199'),
('002326cf0b76bd0d','1240','Avon Avenue SW','Atlanta','GA','30310','-84.4285606','33.721957'),
('00236f2dabaf850a','931','931 Gresham Avenue SE','Atlanta/DeKalb','GA','30316','-84.3464469','33.7280391'),
('0023723b97936a61','607','Eagles Crest Village Lane','Roswell','GA','30076','-84.3380329','34.0400728'),
('00237aac8e482dd1','2004','Summerbrook Drive','Sandy Springs','GA','30350','-84.335068','33.9917375'),
('002396b74372121b','6222','Rockaway Road','South Fulton','GA','30349','-84.4736215','33.5835231'),
('0023aee3708d4fd8','1911','Greenhouse Drive','Roswell','GA','30076','-84.3220738','34.0546663'),
('0023b3abcd6db773','1292','Liberty Parkway NW','Atlanta','GA','30318','-84.4414843','33.8183291'),
('0023cc71f1101497','6050','Roswell Road','Sandy Springs','GA','30328','-84.3801514','33.9199403'),
('0023da7db8453ffb','98','Ardmore Place NW','Atlanta','GA','30309','-84.3966832','33.8039511'),
('00245463cc14727f','5550','Mount Vernon Parkway','Sandy Springs','GA','30327','-84.4114118','33.9071195'),
('0024624f6df6654c','9578','Lakeview Circle','Union City','GA','30291','-84.5728804','33.6014763'),
('0024a51fd39114d5','375','Highland Avenue NE','Atlanta','GA','30312','-84.3754086','33.7609252'),
('0024b6df1bbafc1b','276','Avalon Square','South Fulton','GA','30213','-84.569553','33.5483574'),
('00253a017923a8e5','210','Cemetery Street','Fairburn','GA','30213','-84.5924259','33.5644753'),
('00253dc4dcdf08cc','1115','Wingate Way','Sandy Springs','GA','30350','-84.3520972','33.9671263'),
('002641794bc4901a','180','Spalding Trail','Sandy Springs','GA','30328','-84.3588127','33.9632698'),
('00267b4ba99f27d1','210','Bent Grass Drive','Roswell','GA','30076','-84.3546195','34.0448967'),
('002690c1e90b04b2','507','Butler National Drive','Johns Creek','GA','30097','-84.1716011','34.0307374'),
('0026ba9cd07348d9','125','Braided Blanket Bluff','Johns Creek','GA','30022','-84.2305277','34.0502106'),
('0026db3e4aeacd79','8674','Arvid Loop','Chattahoochee Hills','GA','30213','-84.67055','33.5723202'),
('0026e0b2b87682ba','1612','Beatie Avenue SW','Atlanta','GA','30310','-84.4106691','33.7109686'),
('002711188487e327','2002','Queen Anne Court','Sandy Springs','GA','30350','-84.3353632','34.0081595'),
('002762459b16db73','190','Kirkwood Road NE','Atlanta/DeKalb','GA','30317','-84.3222717','33.7576827'),
('002776a4da6e4f82','13415','Holly Road','Milton','GA','30075','-84.3776475','34.1097676'),
('00278c398facc8e2','819','Jamont Circle','Johns Creek','GA','30022','-84.2621368','34.0155449'),
('0027bcc2c9009dac','8661','Campbellton Redwine Road','Chattahoochee Hills','GA','30268','-84.8122757','33.5227248'),
('002810adf7c97ea0','1675','Fernleaf Circle NW','Atlanta','GA','30318','-84.4422917','33.8214046'),
('00298a5724d8dbfa','2326','Baywood Drive SE','Atlanta','GA','30315','-84.3869077','33.6915809'),
('00299c579bdaedf7','7526','Deer Creek Drive','Union City','GA','30291','-84.5619067','33.5821592'),
('0029a97bc5d630f0','1226','Cahaba Drive SW','Atlanta','GA','30311','-84.4479172','33.7217926'),
('0029c2598e5b622b','2040','Bushy Run','Roswell','GA','30075','-84.3947392','34.0206214'),
('0029cae72b7dea75','878','Peachtree Street NE','Atlanta','GA','30309','-84.3848931','33.7788281');

-- ---------------------------------------------------------------------------
-- Deterministic per-address plan: type, dimensions, sale, owner
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE _seed AS
SELECT s2.*,
    ROUND(CASE s2.pt_code
        WHEN 'RES_SFD' THEN s2.gla * (180 + 220 * pg_temp.hrand(s2.source_id || ':psf'))
        WHEN 'MF_MID'  THEN s2.unit_count * (120000 + 180000 * pg_temp.hrand(s2.source_id || ':ppu'))
        WHEN 'COM_OFF' THEN s2.rba * (140 + 260 * pg_temp.hrand(s2.source_id || ':psf'))
        WHEN 'COM_RET' THEN s2.rba * (120 + 200 * pg_temp.hrand(s2.source_id || ':psf'))
        WHEN 'COM_IND' THEN s2.rba * (70 + 120 * pg_temp.hrand(s2.source_id || ':psf'))
        ELSE                s2.land_sqft * (3 + 12 * pg_temp.hrand(s2.source_id || ':psf'))
    END::NUMERIC, -3) AS est_value
FROM (
    SELECT s1.*,
        CASE WHEN s1.pt_code = 'RES_SFD'
             THEN (900 + FLOOR(3600 * pg_temp.hrand(s1.source_id || ':gla')))::INT
        END AS gla,
        CASE WHEN s1.pt_code IN ('MF_MID', 'COM_OFF', 'COM_RET', 'COM_IND')
             THEN (8000 + FLOOR(120000 * pg_temp.hrand(s1.source_id || ':rba')))::INT
        END AS rba,
        CASE WHEN s1.pt_code = 'MF_MID'
             THEN (40 + FLOOR(260 * pg_temp.hrand(s1.source_id || ':units')))::INT
        END AS unit_count,
        CASE WHEN s1.pt_code = 'COM_IND'
             THEN (18 + FLOOR(18 * pg_temp.hrand(s1.source_id || ':clear')))::NUMERIC(5,1)
        END AS clear_height,
        CASE
            WHEN s1.pt_code = 'RES_SFD' THEN (6000 + FLOOR(39000 * pg_temp.hrand(s1.source_id || ':lot')))::NUMERIC
            WHEN s1.pt_code = 'LND_COM' THEN (40000 + FLOOR(400000 * pg_temp.hrand(s1.source_id || ':lot')))::NUMERIC
            ELSE (20000 + FLOOR(200000 * pg_temp.hrand(s1.source_id || ':lot')))::NUMERIC
        END AS land_sqft,
        CASE WHEN s1.pt_code = 'RES_SFD'
             THEN (1925 + FLOOR(95 * pg_temp.hrand(s1.source_id || ':yb')))::INT
             ELSE (1960 + FLOOR(60 * pg_temp.hrand(s1.source_id || ':yb')))::INT
        END AS year_built,
        pg_temp.hrand(s1.source_id || ':sale') < 0.70 AS has_sale,
        (DATE '2019-01-01' + FLOOR(2500 * pg_temp.hrand(s1.source_id || ':saledate'))::INT) AS sale_date,
        pg_temp.hrand(s1.source_id || ':verified') < 0.35 AS is_verified,
        pg_temp.hrand(s1.source_id || ':listing') < 0.06 AS has_listing,
        pg_temp.hrand(s1.source_id || ':mortgage') < 0.50 AS has_mortgage,
        pg_temp.hrand(s1.source_id || ':delinquent') < 0.08 AS is_delinquent,
        FLOOR(60 * pg_temp.hrand(s1.source_id || ':owner'))::INT AS owner_bucket
    FROM (
        SELECT a.*, z.county_fips, z.county_name,
            CASE
                WHEN pg_temp.hrand(a.source_id || ':type') < 0.72 THEN 'RES_SFD'
                WHEN pg_temp.hrand(a.source_id || ':type') < 0.82 THEN 'MF_MID'
                WHEN pg_temp.hrand(a.source_id || ':type') < 0.88 THEN 'COM_OFF'
                WHEN pg_temp.hrand(a.source_id || ':type') < 0.93 THEN 'COM_RET'
                WHEN pg_temp.hrand(a.source_id || ':type') < 0.97 THEN 'COM_IND'
                ELSE 'LND_COM'
            END AS pt_code
        FROM _seed_addresses a
        JOIN us_zips z ON z.zip = a.postal_code
        WHERE z.county_fips IS NOT NULL
    ) s1
) s2;

-- ---------------------------------------------------------------------------
-- Providers, users, classification, jurisdictions
-- ---------------------------------------------------------------------------
INSERT INTO data_providers (id, code, name, category, kind)
VALUES (pg_temp.duuid('provider', 'dev_seed_bulk'),
        'dev_seed_bulk', 'OpenComps Dev Seed', 'user_contributed', 'bulk_feed');

INSERT INTO users (id, email, display_name)
VALUES
    (pg_temp.duuid('user', 'dev'), 'dev@opencomps.local', 'Dev Seeder'),
    (pg_temp.duuid('user', 'reviewer'), 'reviewer@opencomps.local', 'Dev Reviewer')
ON CONFLICT (email) DO NOTHING;

-- comp_types/property_types are canonical vocabulary shipped by the schema
-- migration; the seed looks them up by code rather than creating them.

-- real counties, resolved through the us_zips reference table
INSERT INTO jurisdictions (id, country, region, name, kind, authority_code)
SELECT DISTINCT pg_temp.duuid('jurisdiction', s.county_fips),
       'US', s.region, s.county_name || ' County', 'county', s.county_fips
FROM _seed s
ON CONFLICT (country, kind, authority_code) WHERE authority_code IS NOT NULL
DO NOTHING;

-- ---------------------------------------------------------------------------
-- Owners: 60 recurring entities so portfolio queries have something to find
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE _owners AS
SELECT b.bucket,
       pg_temp.duuid('owner', b.bucket::TEXT) AS id,
       CASE WHEN b.is_person THEN b.first_name || ' ' || b.last_name
            ELSE b.stem || ' ' || b.noun || ' LLC'
       END AS name,
       CASE WHEN b.is_person THEN 'individual'::owner_kind ELSE 'llc'::owner_kind END AS kind
FROM (
    SELECT i AS bucket,
        pg_temp.hrand('owner-kind:' || i) < 0.55 AS is_person,
        (ARRAY['James','Maria','Robert','Aisha','David','Wei','Sarah','Miguel',
               'Karen','Samuel','Nia','Thomas','Grace','Andre','Linda','Marcus'])
            [1 + FLOOR(16 * pg_temp.hrand('owner-first:' || i))::INT] AS first_name,
        (ARRAY['Walker','Johnson','Chen','Patel','Nguyen','Garcia','Smith','Brooks',
               'Kim','Okafor','Ramirez','Thompson','Lee','Jackson','Alvarez','Wright'])
            [1 + FLOOR(16 * pg_temp.hrand('owner-last:' || i))::INT] AS last_name,
        (ARRAY['Peachtree','Piedmont','Chattahoochee','Buckhead','Ansley',
               'Vinings','Midtown','Westside','Ponce','Decatur'])
            [1 + FLOOR(10 * pg_temp.hrand('owner-stem:' || i))::INT] AS stem,
        (ARRAY['Capital','Holdings','Partners','Properties','Ventures','Realty'])
            [1 + FLOOR(6 * pg_temp.hrand('owner-noun:' || i))::INT] AS noun
    FROM GENERATE_SERIES(0, 59) AS i
) b;

INSERT INTO owners (id, name, normalized_name, kind)
SELECT id, name, LOWER(name), kind FROM _owners;

-- ---------------------------------------------------------------------------
-- Addresses, properties, identifiers, parcels
-- ---------------------------------------------------------------------------
INSERT INTO addresses (
    id, country, street_number, street_name, locality, region, postal_code,
    admin_area, address_hash, location, is_standardized, standardization_source
)
SELECT pg_temp.duuid('address', s.source_id),
       'US', NULLIF(s.street_number, ''), s.street_name, s.locality, s.region,
       s.postal_code, s.county_name || ' County',
       'dev-seed:' || s.source_id,
       ST_SetSRID(ST_MakePoint(NULLIF(s.lon,'')::DOUBLE PRECISION, NULLIF(s.lat,'')::DOUBLE PRECISION), 4326)::GEOGRAPHY,
       TRUE, 'dev_seed'
FROM _seed s;

INSERT INTO properties (id, name, property_type_id, situs_address_id, location, metadata)
SELECT pg_temp.duuid('property', s.source_id),
       TRIM(s.street_number || ' ' || s.street_name),
       (SELECT id FROM property_types WHERE code = s.pt_code),
       pg_temp.duuid('address', s.source_id),
       ST_SetSRID(ST_MakePoint(NULLIF(s.lon,'')::DOUBLE PRECISION, NULLIF(s.lat,'')::DOUBLE PRECISION), 4326)::GEOGRAPHY,
       JSONB_BUILD_OBJECT('seed_source_id', s.source_id, 'dev_seed', TRUE)
FROM _seed s;

INSERT INTO property_identifiers (property_id, scheme, namespace, value, provider_id)
SELECT pg_temp.duuid('property', s.source_id),
       'dev_seed_address_id', 'dev_seed', s.source_id,
       pg_temp.duuid('provider', 'dev_seed_bulk')
FROM _seed s;

INSERT INTO parcels (
    id, jurisdiction_id, country, authority_code, parcel_number,
    normalized_parcel_number, land_area, legal_description
)
SELECT pg_temp.duuid('parcel', s.source_id),
       j.id, 'US', s.county_fips,
       'DEV-' || UPPER(SUBSTR(s.source_id, 1, 10)),
       'DEV' || UPPER(SUBSTR(s.source_id, 1, 10)),
       s.land_sqft,
       'Dev seed parcel for ' || TRIM(s.street_number || ' ' || s.street_name)
FROM _seed s
JOIN jurisdictions j
  ON j.authority_code = s.county_fips AND j.kind = 'county' AND j.country = 'US';

INSERT INTO property_parcels (property_id, parcel_id, is_primary, started_on)
SELECT pg_temp.duuid('property', s.source_id),
       pg_temp.duuid('parcel', s.source_id),
       TRUE,
       DATE '2010-01-01' + FLOOR(3000 * pg_temp.hrand(s.source_id || ':pp'))::INT
FROM _seed s;

-- ---------------------------------------------------------------------------
-- Physical details by asset class
-- ---------------------------------------------------------------------------
INSERT INTO residential_details (
    property_id, gla, bedrooms, bathrooms, bathrooms_full, bathrooms_half,
    stories, year_built, garage_spaces, lot_size, condition_rating, quality_rating
)
SELECT pg_temp.duuid('property', s.source_id),
       s.gla,
       (2 + FLOOR(4 * pg_temp.hrand(s.source_id || ':bed')))::INT,
       (1 + FLOOR(3 * pg_temp.hrand(s.source_id || ':bathf')))::INT
           + CASE WHEN pg_temp.hrand(s.source_id || ':bathh') < 0.4 THEN 0.5 ELSE 0 END,
       (1 + FLOOR(3 * pg_temp.hrand(s.source_id || ':bathf')))::INT,
       CASE WHEN pg_temp.hrand(s.source_id || ':bathh') < 0.4 THEN 1 ELSE 0 END,
       CASE WHEN pg_temp.hrand(s.source_id || ':story') < 0.5 THEN 1.0 ELSE 2.0 END,
       s.year_built,
       FLOOR(4 * pg_temp.hrand(s.source_id || ':garage'))::INT,
       s.land_sqft,
       'C' || (2 + FLOOR(4 * pg_temp.hrand(s.source_id || ':cond')))::INT,
       'Q' || (2 + FLOOR(4 * pg_temp.hrand(s.source_id || ':qual')))::INT
FROM _seed s
WHERE s.pt_code = 'RES_SFD';

INSERT INTO commercial_details (
    property_id, rentable_building_area, land_area, stories, year_built,
    unit_count, occupancy_pct, clear_height, tenancy, building_class
)
SELECT pg_temp.duuid('property', s.source_id),
       s.rba, s.land_sqft,
       (1 + FLOOR(12 * pg_temp.hrand(s.source_id || ':floors')))::INT,
       s.year_built,
       s.unit_count,
       ROUND((70 + 30 * pg_temp.hrand(s.source_id || ':occ'))::NUMERIC, 1),
       s.clear_height,
       CASE WHEN pg_temp.hrand(s.source_id || ':tenancy') < 0.6
            THEN 'multi_tenant' ELSE 'single_tenant' END,
       (ARRAY['A','B','C'])[1 + FLOOR(3 * pg_temp.hrand(s.source_id || ':class'))::INT]
FROM _seed s
WHERE s.pt_code IN ('MF_MID', 'COM_OFF', 'COM_RET', 'COM_IND');

INSERT INTO land_details (property_id, lot_size, zoning, land_use, topography, utilities)
SELECT pg_temp.duuid('property', s.source_id),
       s.land_sqft,
       (ARRAY['C-1','C-2','M-1','MU-2','R-4'])[1 + FLOOR(5 * pg_temp.hrand(s.source_id || ':zone'))::INT],
       'vacant',
       (ARRAY['level','sloping','rolling'])[1 + FLOOR(3 * pg_temp.hrand(s.source_id || ':topo'))::INT],
       ARRAY['water', 'sewer', 'electric']
FROM _seed s
WHERE s.pt_code = 'LND_COM';

-- ---------------------------------------------------------------------------
-- Transfers, ownership, sale comps (for the ~70% that traded)
-- ---------------------------------------------------------------------------
INSERT INTO property_transfers (
    id, property_id, parcel_id, transfer_kind, recorded_on, effective_on,
    consideration, document_number, grantee_owner_id, verification_status
)
SELECT pg_temp.duuid('transfer', s.source_id),
       pg_temp.duuid('property', s.source_id),
       pg_temp.duuid('parcel', s.source_id),
       'warranty_deed', s.sale_date + 2, s.sale_date,
       s.est_value,
       'WD-' || EXTRACT(YEAR FROM s.sale_date) || '-DEV-' || UPPER(SUBSTR(s.source_id, 1, 8)),
       pg_temp.duuid('owner', s.owner_bucket::TEXT),
       CASE WHEN s.is_verified THEN 'verified' ELSE 'unverified' END::verification_status
FROM _seed s
WHERE s.has_sale;

INSERT INTO ownership_periods (
    id, property_id, started_on, acquired_via_transfer_id,
    contributed_by_id, verification_status
)
SELECT pg_temp.duuid('op', s.source_id),
       pg_temp.duuid('property', s.source_id),
       CASE WHEN s.has_sale THEN s.sale_date
            ELSE DATE '2012-01-01' + FLOOR(3600 * pg_temp.hrand(s.source_id || ':acq'))::INT
       END,
       CASE WHEN s.has_sale THEN pg_temp.duuid('transfer', s.source_id) END,
       pg_temp.duuid('user', 'dev'),
       CASE WHEN s.is_verified THEN 'verified' ELSE 'unverified' END::verification_status
FROM _seed s;

INSERT INTO ownership_interests (ownership_period_id, owner_id, ownership_pct, vesting, role)
SELECT pg_temp.duuid('op', s.source_id),
       pg_temp.duuid('owner', s.owner_bucket::TEXT),
       100.000, 'fee simple', 'owner'
FROM _seed s;

INSERT INTO property_sales (
    id, property_id, transfer_id, comp_type_id, sale_date, sale_price,
    sale_type, buyer_name, price_per_area, cap_rate, price_per_unit,
    unit_count_at_sale, contributed_by_id, verification_status
)
SELECT pg_temp.duuid('sale', s.source_id),
       pg_temp.duuid('property', s.source_id),
       pg_temp.duuid('transfer', s.source_id),
       (SELECT ct.id FROM comp_types ct
        JOIN property_types pt ON pt.comp_type_id = ct.id
        WHERE pt.code = s.pt_code),
       s.sale_date, s.est_value,
       CASE WHEN pg_temp.hrand(s.source_id || ':saletype') < 0.90
            THEN 'arms_length' ELSE 'reo' END::sale_type,
       o.name,
       CASE WHEN s.pt_code = 'RES_SFD' THEN ROUND(s.est_value / s.gla, 2)
            WHEN s.rba IS NOT NULL THEN ROUND(s.est_value / s.rba, 2)
       END,
       CASE WHEN s.pt_code IN ('MF_MID', 'COM_OFF', 'COM_RET', 'COM_IND')
            THEN ROUND((4.5 + 4 * pg_temp.hrand(s.source_id || ':cap'))::NUMERIC, 2)
       END,
       CASE WHEN s.pt_code = 'MF_MID' THEN ROUND(s.est_value / s.unit_count, 2) END,
       CASE WHEN s.pt_code = 'MF_MID' THEN s.unit_count END,
       pg_temp.duuid('user', 'dev'),
       CASE WHEN s.is_verified THEN 'verified' ELSE 'unverified' END::verification_status
FROM _seed s
JOIN _owners o ON o.bucket = s.owner_bucket
WHERE s.has_sale;

-- ---------------------------------------------------------------------------
-- Assessments and tax bills for every parcel (2024 roll)
-- ---------------------------------------------------------------------------
INSERT INTO assessments (
    id, parcel_id, jurisdiction_id, tax_year, roll_type, assessed_land,
    assessed_improvements, assessed_total, market_value, taxable_value,
    verification_status
)
SELECT pg_temp.duuid('assessment', s.source_id),
       pg_temp.duuid('parcel', s.source_id),
       j.id, 2024, 'original',
       ROUND(mv.market * 0.4 * 0.3, 2),
       ROUND(mv.market * 0.4 * 0.7, 2),
       ROUND(mv.market * 0.4, 2),
       ROUND(mv.market, 2),
       ROUND(mv.market * 0.4, 2),
       'unverified'
FROM _seed s
JOIN jurisdictions j
  ON j.authority_code = s.county_fips AND j.kind = 'county' AND j.country = 'US'
CROSS JOIN LATERAL (
    SELECT (s.est_value * (0.90 + 0.15 * pg_temp.hrand(s.source_id || ':mv')))::NUMERIC AS market
) mv;

INSERT INTO tax_bills (
    id, parcel_id, jurisdiction_id, tax_year, amount_billed, amount_paid,
    is_delinquent, delinquent_amount
)
SELECT pg_temp.duuid('tax_bill', s.source_id),
       pg_temp.duuid('parcel', s.source_id),
       j.id, 2024,
       bill.amount,
       CASE WHEN s.is_delinquent THEN 0 ELSE bill.amount END,
       s.is_delinquent,
       CASE WHEN s.is_delinquent THEN ROUND(bill.amount * 1.06, 2) END
FROM _seed s
JOIN jurisdictions j
  ON j.authority_code = s.county_fips AND j.kind = 'county' AND j.country = 'US'
CROSS JOIN LATERAL (
    SELECT ROUND(s.est_value * 0.4 * 0.033, 2) AS amount
) bill;

-- ---------------------------------------------------------------------------
-- Debt on about half the traded properties
-- ---------------------------------------------------------------------------
INSERT INTO property_mortgages (
    id, property_id, parcel_id, recording_date, loan_amount, lender_name,
    borrower_owner_id, loan_type, interest_rate, term_months, maturity_date,
    lien_position, status, related_transfer_id, verification_status
)
SELECT pg_temp.duuid('mortgage', s.source_id),
       pg_temp.duuid('property', s.source_id),
       pg_temp.duuid('parcel', s.source_id),
       s.sale_date + 2,
       ROUND((s.est_value * (0.55 + 0.20 * pg_temp.hrand(s.source_id || ':ltv')))::NUMERIC, -3),
       (ARRAY['Peachtree Bank','Truist','Synovus','Ameris Bank','Regions',
              'BANK5 CMBS Trust'])[1 + FLOOR(6 * pg_temp.hrand(s.source_id || ':lender'))::INT],
       pg_temp.duuid('owner', s.owner_bucket::TEXT),
       CASE WHEN s.pt_code = 'RES_SFD' THEN 'conventional' ELSE 'commercial' END,
       ROUND((3.5 + 4 * pg_temp.hrand(s.source_id || ':rate'))::NUMERIC, 3),
       loan.term,
       (s.sale_date + (loan.term || ' months')::INTERVAL)::DATE,
       1, 'active',
       pg_temp.duuid('transfer', s.source_id),
       'unverified'
FROM _seed s
CROSS JOIN LATERAL (
    SELECT CASE WHEN s.pt_code = 'RES_SFD' THEN 360
                ELSE (60 + FLOOR(5 * pg_temp.hrand(s.source_id || ':term'))::INT * 12)
           END AS term
) loan
WHERE s.has_sale AND s.has_mortgage;

-- ---------------------------------------------------------------------------
-- Market observations: multifamily floorplan rents, commercial leases,
-- active for-sale listings
-- ---------------------------------------------------------------------------
INSERT INTO property_unit_rents (
    id, property_id, comp_type_id, unit_type, unit_area, bedrooms, bathrooms,
    unit_count, rate_amount, rate_period, rate_basis, rate_type, observed_on,
    contributed_by_id, verification_status
)
SELECT pg_temp.duuid('rent:' || fp.unit_type, s.source_id),
       pg_temp.duuid('property', s.source_id),
       (SELECT id FROM comp_types WHERE code = 'multifamily'),
       fp.unit_type, fp.area, fp.beds, fp.baths,
       GREATEST(1, s.unit_count / 2),
       ROUND((fp.base + fp.spread * pg_temp.hrand(s.source_id || ':rent:' || fp.unit_type))::NUMERIC, 0),
       'monthly', 'per_unit', 'asking',
       DATE '2026-05-01',
       pg_temp.duuid('user', 'dev'), 'unverified'
FROM _seed s
CROSS JOIN (VALUES
    ('1BR/1BA', 760, 1, 1.0, 1200, 800),
    ('2BR/2BA', 1120, 2, 2.0, 1650, 1100)
) AS fp(unit_type, area, beds, baths, base, spread)
WHERE s.pt_code = 'MF_MID';

INSERT INTO property_leases (
    id, property_id, comp_type_id, lessee_name, lease_type, transaction_type,
    commencement_date, expiration_date, term_months, leased_area, rent_amount,
    rent_period, starting_rent_per_area, annual_rent, contributed_by_id,
    verification_status
)
SELECT pg_temp.duuid('lease', s.source_id),
       pg_temp.duuid('property', s.source_id),
       (SELECT ct.id FROM comp_types ct
        JOIN property_types pt ON pt.comp_type_id = ct.id
        WHERE pt.code = s.pt_code),
       (ARRAY['Summit Services','Bluebird Retail','Apex Logistics','Ivy Health',
              'Terra Foods','Nimbus Tech'])[1 + FLOOR(6 * pg_temp.hrand(s.source_id || ':tenant'))::INT],
       CASE s.pt_code WHEN 'COM_OFF' THEN 'modified_gross' ELSE 'triple_net' END::lease_type,
       'new_lease',
       lease.commencement,
       (lease.commencement + (lease.term || ' months')::INTERVAL)::DATE,
       lease.term,
       lease.area,
       lease.rate, 'per_area_annual', lease.rate,
       ROUND(lease.rate * lease.area, 2),
       pg_temp.duuid('user', 'dev'),
       CASE WHEN s.is_verified THEN 'verified' ELSE 'unverified' END::verification_status
FROM _seed s
CROSS JOIN LATERAL (
    SELECT (DATE '2023-01-01' + FLOOR(1100 * pg_temp.hrand(s.source_id || ':lc'))::INT) AS commencement,
           (36 + FLOOR(7 * pg_temp.hrand(s.source_id || ':lterm'))::INT * 12) AS term,
           GREATEST(1200, (s.rba * (0.15 + 0.35 * pg_temp.hrand(s.source_id || ':larea')))::INT) AS area,
           ROUND(CASE s.pt_code
               WHEN 'COM_OFF' THEN 24 + 22 * pg_temp.hrand(s.source_id || ':lrate')
               WHEN 'COM_RET' THEN 18 + 24 * pg_temp.hrand(s.source_id || ':lrate')
               ELSE 6 + 8 * pg_temp.hrand(s.source_id || ':lrate')
           END::NUMERIC, 2) AS rate
) lease
WHERE s.pt_code IN ('COM_OFF', 'COM_RET', 'COM_IND');

INSERT INTO property_listings (
    id, property_id, listing_kind, status, list_price, listed_on,
    listing_brokerage, verification_status
)
SELECT pg_temp.duuid('listing', s.source_id),
       pg_temp.duuid('property', s.source_id),
       'for_sale', 'active',
       ROUND((s.est_value * 1.05)::NUMERIC, -3),
       DATE '2026-01-01' + FLOOR(150 * pg_temp.hrand(s.source_id || ':listed'))::INT,
       'OpenComps Dev Brokerage',
       'unverified'
FROM _seed s
WHERE s.has_listing;

COMMIT;

-- what got seeded
SELECT 'properties' AS entity, COUNT(*) FROM properties WHERE metadata ? 'dev_seed'
UNION ALL SELECT 'parcels', COUNT(*) FROM parcels WHERE parcel_number LIKE 'DEV-%'
UNION ALL SELECT 'owners', COUNT(*) FROM owners
UNION ALL SELECT 'sales', COUNT(*) FROM property_sales
UNION ALL SELECT 'leases', COUNT(*) FROM property_leases
UNION ALL SELECT 'unit_rents', COUNT(*) FROM property_unit_rents
UNION ALL SELECT 'assessments', COUNT(*) FROM assessments
UNION ALL SELECT 'tax_bills', COUNT(*) FROM tax_bills
UNION ALL SELECT 'mortgages', COUNT(*) FROM property_mortgages
UNION ALL SELECT 'listings', COUNT(*) FROM property_listings
ORDER BY 1;
