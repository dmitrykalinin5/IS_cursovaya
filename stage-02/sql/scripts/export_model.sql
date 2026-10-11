\set ON_ERROR_STOP on
SELECT jsonb_pretty(jsonb_build_object(
 'tables',(SELECT jsonb_agg(jsonb_build_object('name',t.table_name,'columns',
  (SELECT jsonb_agg(jsonb_build_object('name',c.column_name,'type',c.data_type,'udt',c.udt_name,
   'domain',c.domain_name,'nullable',c.is_nullable,'default',c.column_default,'identity',c.is_identity) ORDER BY c.ordinal_position)
   FROM information_schema.columns c WHERE c.table_schema=t.table_schema AND c.table_name=t.table_name),
  'constraints',(SELECT jsonb_agg(jsonb_build_object('name',con.conname,'kind',con.contype,
    'definition',pg_get_constraintdef(con.oid))) FROM pg_constraint con WHERE con.conrelid=('labreserve.'||t.table_name)::regclass)
 )) FROM information_schema.tables t WHERE t.table_schema='labreserve' AND t.table_type='BASE TABLE'),
 'foreign_keys',(SELECT jsonb_agg(jsonb_build_object('from',c.conrelid::regclass::text,'to',c.confrelid::regclass::text,
   'definition',pg_get_constraintdef(c.oid),'name',c.conname)) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname='labreserve' AND c.contype='f'),
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'result',pg_get_function_result(p.oid),
  'definer',p.prosecdef)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='labreserve'),
 'indexes',(SELECT jsonb_agg(jsonb_build_object('name',indexname,'definition',indexdef)) FROM pg_indexes WHERE schemaname='labreserve'),
 'triggers',(SELECT jsonb_agg(jsonb_build_object('table',c.relname,'name',t.tgname,'definition',pg_get_triggerdef(t.oid)))
 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='labreserve' AND NOT t.tgisinternal)
));
