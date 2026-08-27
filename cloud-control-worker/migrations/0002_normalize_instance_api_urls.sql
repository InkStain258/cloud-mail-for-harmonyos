UPDATE mail_instance
SET api_base_url = 'https://' || origin_host || '/' ||
    ltrim(substr(api_base_url, length('https://' || origin_host) + 1), '/'),
    update_time = CURRENT_TIMESTAMP
WHERE api_base_url LIKE 'https://' || origin_host || '//%';
