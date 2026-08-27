CREATE TABLE test_assertion (
  name TEXT PRIMARY KEY,
  passed INTEGER NOT NULL CHECK (passed = 1)
);

INSERT INTO platform_user
  (platform_user_id, huawei_user_id, open_id, nick_name, platform_role)
VALUES
  (900001, 'test-super-admin', 'test-super-admin', 'Test Admin', 'SUPER_ADMIN'),
  (900002, 'test-real-user', 'test-real-user', 'Real User', 'MEMBER');

INSERT INTO mail_instance
  (instance_id, display_name, api_base_url, origin_host, created_by)
VALUES
  ('riordon-cloud-mail', 'Anchor', 'https://anchor.test/api', 'anchor.test', 900001);

INSERT INTO instance_binding
  (binding_id, platform_user_id, instance_id, local_user_key, local_email, local_role_name, instance_role)
VALUES
  (900001, 900001, 'riordon-cloud-mail', 'admin', 'admin@anchor.test', 'admin', 'INSTANCE_OWNER'),
  (900002, 900002, 'riordon-cloud-mail', 'real', 'real@anchor.test', 'user', 'MEMBER');

INSERT INTO legacy_anchor_binding
  (source_instance_id, source_account_id, masked_huawei_user_id, nick_name, primary_email, import_marker)
WITH RECURSIVE numbers(value) AS (
  SELECT 1 UNION ALL SELECT value + 1 FROM numbers WHERE value < 13
)
SELECT 'riordon-cloud-mail', value, 'masked-' || value, 'Legacy ' || value,
  CASE WHEN value = 1 THEN 'real@anchor.test' ELSE 'legacy-' || value || '@anchor.test' END,
  'first-import'
FROM numbers;

INSERT INTO test_assertion
SELECT 'thirteen_imported', CASE WHEN COUNT(*) = 13 THEN 1 ELSE 0 END
FROM legacy_anchor_binding WHERE source_instance_id = 'riordon-cloud-mail';

-- Repeating the same source IDs is an upsert, not a duplicate import.
INSERT INTO legacy_anchor_binding
  (source_instance_id, source_account_id, masked_huawei_user_id, nick_name, primary_email, import_marker)
SELECT source_instance_id, source_account_id, masked_huawei_user_id, nick_name, primary_email, 'second-import'
FROM legacy_anchor_binding WHERE source_instance_id = 'riordon-cloud-mail'
ON CONFLICT(source_instance_id, source_account_id) DO UPDATE SET
  import_marker = excluded.import_marker, update_time = CURRENT_TIMESTAMP;

INSERT INTO test_assertion
SELECT 'idempotent_import', CASE WHEN COUNT(*) = 13 THEN 1 ELSE 0 END
FROM legacy_anchor_binding WHERE source_instance_id = 'riordon-cloud-mail';

-- The admin list must hide a legacy row after the matching real platform binding exists.
INSERT INTO test_assertion
SELECT 'real_user_deduplicated', CASE WHEN COUNT(*) = 12 THEN 1 ELSE 0 END
FROM legacy_anchor_binding l
WHERE l.source_instance_id = 'riordon-cloud-mail'
  AND NOT EXISTS (
    SELECT 1 FROM instance_binding b
    WHERE b.instance_id = l.source_instance_id AND b.status = 'ACTIVE'
      AND lower(b.local_email) = lower(l.primary_email)
  );

INSERT INTO test_assertion
SELECT 'owner_guard_exists', CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END
FROM pragma_index_list('instance_binding')
WHERE name = 'ux_instance_single_active_owner' AND "unique" = 1;

SELECT name, passed FROM test_assertion ORDER BY name;

-- Exercise the same UNION shape used by the administrator list: real users and
-- unmatched legacy users share one ordered, paged result without exposing a
-- masked ID as a platform identity.
WITH visible_legacy AS (
  SELECT l.legacy_binding_id, l.source_instance_id, l.masked_huawei_user_id,
    l.nick_name, l.avatar_url, l.primary_email,
    COALESCE(NULLIF(l.source_create_time, ''), l.create_time) AS source_create_time
  FROM legacy_anchor_binding l
  WHERE l.source_instance_id = 'riordon-cloud-mail'
    AND NOT EXISTS (
      SELECT 1 FROM instance_binding xb
      WHERE xb.instance_id = l.source_instance_id AND xb.status = 'ACTIVE'
        AND lower(xb.local_email) = lower(l.primary_email)
    )
),
all_users AS (
  SELECT 'PLATFORM' AS record_type, p.platform_user_id, p.huawei_user_id,
    p.nick_name, p.avatar_url, p.platform_role, p.create_time,
    NULL AS legacy_binding_id, NULL AS source_instance_id, NULL AS legacy_email
  FROM platform_user p WHERE p.status = 'ACTIVE'
  UNION ALL
  SELECT 'LEGACY', -l.legacy_binding_id, l.masked_huawei_user_id,
    l.nick_name, l.avatar_url, 'MEMBER', l.source_create_time,
    l.legacy_binding_id, l.source_instance_id, l.primary_email
  FROM visible_legacy l
),
filtered_users AS (
  SELECT * FROM all_users
),
paged_users AS (
  SELECT * FROM filtered_users
  ORDER BY create_time DESC, platform_user_id DESC LIMIT 20 OFFSET 0
)
SELECT pu.platform_user_id, pu.huawei_user_id, pu.create_time,
  b.binding_id, b.instance_id, b.local_email, b.instance_role, b.verified_time
FROM paged_users pu
LEFT JOIN instance_binding b ON b.platform_user_id = pu.platform_user_id
  AND pu.record_type = 'PLATFORM' AND b.status = 'ACTIVE'
WHERE pu.record_type = 'PLATFORM'
UNION ALL
SELECT pu.platform_user_id, pu.huawei_user_id, pu.create_time,
  -pu.legacy_binding_id, pu.source_instance_id, pu.legacy_email, 'MEMBER', pu.create_time
FROM paged_users pu
WHERE pu.record_type = 'LEGACY'
ORDER BY create_time DESC, platform_user_id DESC, verified_time DESC, binding_id DESC;
