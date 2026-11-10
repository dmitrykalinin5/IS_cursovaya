-- Installation metadata lives in a comment, not in an extra model table.
CREATE FUNCTION pg_temp.lr_manifest() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE note text; prefix text:=E'LabReserve manifest v2\n';
BEGIN
 note:=obj_description(to_regclass('s466088.lr_app_user'),'pg_class');
 IF note IS NULL OR left(note,length(prefix))<>prefix THEN RETURN NULL; END IF;
 RETURN substring(note FROM length(prefix)+1)::jsonb;
END $$;
