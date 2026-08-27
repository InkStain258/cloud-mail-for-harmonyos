PRAGMA foreign_keys = ON;

-- Keep the earliest active owner if an older deployment ever admitted more than one.
UPDATE instance_binding
SET instance_role = 'INSTANCE_ADMIN', update_time = CURRENT_TIMESTAMP
WHERE status = 'ACTIVE'
  AND instance_role = 'INSTANCE_OWNER'
  AND binding_id NOT IN (
    SELECT MIN(binding_id)
    FROM instance_binding
    WHERE status = 'ACTIVE' AND instance_role = 'INSTANCE_OWNER'
    GROUP BY instance_id
  );

CREATE UNIQUE INDEX IF NOT EXISTS ux_instance_single_active_owner
  ON instance_binding(instance_id)
  WHERE status = 'ACTIVE' AND instance_role = 'INSTANCE_OWNER';

-- Legacy Huawei bindings are deliberately kept separate from platform_user.
-- The legacy API exposes only a masked Huawei identifier, which must not be
-- promoted into a real platform identity.
CREATE TABLE IF NOT EXISTS legacy_anchor_binding (
  legacy_binding_id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_instance_id TEXT NOT NULL,
  source_account_id INTEGER NOT NULL,
  masked_huawei_user_id TEXT NOT NULL DEFAULT '',
  nick_name TEXT,
  avatar_url TEXT,
  primary_email TEXT NOT NULL,
  profile_update_time TEXT,
  source_create_time TEXT,
  import_marker TEXT NOT NULL,
  create_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  update_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (source_instance_id, source_account_id),
  FOREIGN KEY (source_instance_id) REFERENCES mail_instance(instance_id)
);

CREATE INDEX IF NOT EXISTS idx_legacy_anchor_email
  ON legacy_anchor_binding(source_instance_id, primary_email);
CREATE INDEX IF NOT EXISTS idx_legacy_anchor_search
  ON legacy_anchor_binding(nick_name, primary_email);
