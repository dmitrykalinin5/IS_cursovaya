\set ON_ERROR_STOP on
-- Catalog only; no SELECT of unrelated lab data. Compare before/after deployment.
SELECT jsonb_build_object(
 'schema_acl',(SELECT nspacl::text FROM pg_namespace WHERE nspname='s466088'),
 'relations',(SELECT jsonb_agg(jsonb_build_object('name',c.relname,'kind',c.relkind,
   'owner',c.relowner,'acl',c.relacl::text,'rls',c.relrowsecurity) ORDER BY c.relname)
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='s466088' AND c.relname NOT LIKE 'lr\_%' ESCAPE '\'),
 'columns',(SELECT jsonb_agg(jsonb_build_object('table',c.relname,'column',a.attname,
   'position',a.attnum,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,
   'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY c.relname,a.attnum)
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid
   LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   WHERE n.nspname='s466088' AND c.relname NOT LIKE 'lr\_%' ESCAPE '\' AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT jsonb_agg(jsonb_build_object('name',c.conname,'definition',pg_get_constraintdef(c.oid)) ORDER BY c.oid)
   FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace
   WHERE n.nspname='s466088' AND c.conname NOT LIKE 'lr\_%' ESCAPE '\'),
 'functions',(SELECT jsonb_agg(jsonb_build_object('name',p.proname,'definition',pg_get_functiondef(p.oid),
   'owner',p.proowner,'acl',p.proacl::text) ORDER BY p.oid)
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='s466088' AND p.proname NOT LIKE 'lr\_%' ESCAPE '\'),
 'triggers',(SELECT jsonb_agg(jsonb_build_object('table',c.relname,'name',t.tgname,
   'definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled) ORDER BY t.oid)
   FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='s466088' AND c.relname NOT LIKE 'lr\_%' ESCAPE '\' AND NOT t.tgisinternal)
);
