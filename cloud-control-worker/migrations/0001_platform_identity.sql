PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS platform_user (
  platform_user_id INTEGER PRIMARY KEY AUTOINCREMENT,
  huawei_user_id TEXT NOT NULL UNIQUE,
  union_id TEXT,
  open_id TEXT NOT NULL,
  nick_name TEXT,
  avatar_url TEXT,
  platform_role TEXT NOT NULL DEFAULT 'MEMBER'
    CHECK (platform_role IN ('SUPER_ADMIN', 'MEMBER')),
  status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE', 'DISABLED')),
  create_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  update_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS mail_instance (
  instance_id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  api_base_url TEXT NOT NULL UNIQUE,
  origin_host TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE', 'DISABLED')),
  created_by INTEGER NOT NULL,
  create_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  update_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (created_by) REFERENCES platform_user(platform_user_id)
);

CREATE TABLE IF NOT EXISTS instance_binding (
  binding_id INTEGER PRIMARY KEY AUTOINCREMENT,
  platform_user_id INTEGER NOT NULL,
  instance_id TEXT NOT NULL,
  local_user_key TEXT NOT NULL,
  local_email TEXT NOT NULL,
  local_role_name TEXT NOT NULL DEFAULT '',
  instance_role TEXT NOT NULL DEFAULT 'MEMBER'
    CHECK (instance_role IN ('INSTANCE_OWNER', 'INSTANCE_ADMIN', 'MEMBER')),
  status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('ACTIVE', 'DISABLED')),
  verified_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  update_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (platform_user_id, instance_id),
  UNIQUE (instance_id, local_user_key),
  FOREIGN KEY (platform_user_id) REFERENCES platform_user(platform_user_id),
  FOREIGN KEY (instance_id) REFERENCES mail_instance(instance_id)
);

CREATE TABLE IF NOT EXISTS platform_audit_log (
  audit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  platform_user_id INTEGER,
  instance_id TEXT,
  action TEXT NOT NULL,
  detail TEXT NOT NULL DEFAULT '',
  create_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (platform_user_id) REFERENCES platform_user(platform_user_id),
  FOREIGN KEY (instance_id) REFERENCES mail_instance(instance_id)
);

CREATE INDEX IF NOT EXISTS idx_instance_binding_user
  ON instance_binding(platform_user_id, status);
CREATE INDEX IF NOT EXISTS idx_instance_binding_instance
  ON instance_binding(instance_id, instance_role, status);
CREATE INDEX IF NOT EXISTS idx_audit_instance_time
  ON platform_audit_log(instance_id, create_time DESC);
