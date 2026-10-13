-- Metadata only: data and sequence values do not change this fingerprint.
-- Include ownership, ACL, columns, constraints, definitions and trigger enablement.
CREATE FUNCTION pg_temp.lr_catalog_fingerprint() RETURNS text
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT md5(COALESCE(string_agg(item,E'\n' ORDER BY item),'')) FROM (
 SELECT 'relation:'||c.relname||':'||c.relkind::text||':'||c.relowner||':'||COALESCE(c.relacl::text,'')||':'||c.relrowsecurity AS item
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='s466088' AND c.relname LIKE 'lr\_%' ESCAPE '\'
 UNION ALL
 SELECT 'column:'||c.relname||':'||a.attname||':'||a.attnum||':'||format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull||':'||a.attidentity::text||':'||COALESCE(pg_get_expr(d.adbin,d.adrelid),'')
 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
 WHERE n.nspname='s466088' AND c.relname LIKE 'lr\_%' ESCAPE '\' AND a.attnum>0 AND NOT a.attisdropped
 UNION ALL
 SELECT 'constraint:'||conname||':'||convalidated||':'||pg_get_constraintdef(c.oid)
 FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace
 WHERE n.nspname='s466088' AND conname LIKE 'lr\_%' ESCAPE '\'
 UNION ALL
 SELECT 'function:'||p.proname||':'||p.proowner||':'||COALESCE(p.proacl::text,'')||':'||pg_get_functiondef(p.oid)
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='s466088' AND p.proname LIKE 'lr\_%' ESCAPE '\'
 UNION ALL
 SELECT 'index:'||c.relname||':'||i.indisvalid||':'||pg_get_indexdef(i.indexrelid)
 FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='s466088' AND c.relname LIKE 'lr\_%' ESCAPE '\'
 UNION ALL
 SELECT 'trigger:'||t.tgname||':'||t.tgenabled::text||':'||pg_get_triggerdef(t.oid)
 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='s466088' AND c.relname LIKE 'lr\_%' ESCAPE '\' AND NOT t.tgisinternal
 UNION ALL
 SELECT 'type:'||t.typname||':'||t.typtype::text||':'||t.typowner||':'||COALESCE(t.typacl::text,'')||':'||t.typbasetype
 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
 WHERE n.nspname='s466088' AND (t.typname LIKE 'lr\_%' ESCAPE '\' OR t.typname LIKE '\_lr\_%' ESCAPE '\')
 ) objects
$$;
