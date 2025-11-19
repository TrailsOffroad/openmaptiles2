DROP TRIGGER IF EXISTS trigger_flag ON land_feature_linestring;
DROP TRIGGER IF EXISTS trigger_store ON land_feature_linestring;
DROP TRIGGER IF EXISTS trigger_refresh ON land_feature_linestring.updates;

CREATE SCHEMA IF NOT EXISTS land_feature_linestring;

CREATE TABLE IF NOT EXISTS land_feature_linestring.osm_ids
(
    osm_id bigint PRIMARY KEY
);

-- etldoc:  land_feature_linestring ->  land_feature_linestring
CREATE OR REPLACE FUNCTION update_land_feature_linestring(full_update boolean) RETURNS void AS
$$
    UPDATE land_feature_linestring
    SET tags = update_tags(tags, geometry)
    WHERE (full_update OR osm_id IN (SELECT osm_id FROM land_feature_linestring.osm_ids))
      AND COALESCE(tags -> 'name:latin', tags -> 'name:nonlatin', tags -> 'name_int') IS NULL
      AND tags != update_tags(tags, geometry)
$$ LANGUAGE SQL;

SELECT update_land_feature_linestring(true);

-- Handle updates

CREATE OR REPLACE FUNCTION land_feature_linestring.store() RETURNS trigger AS
$$
BEGIN
    INSERT INTO land_feature_linestring.osm_ids VALUES (NEW.osm_id) ON CONFLICT (osm_id) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS land_feature_linestring.updates
(
    id serial PRIMARY KEY,
    t  text,
    UNIQUE (t)
);
CREATE OR REPLACE FUNCTION land_feature_linestring.flag() RETURNS trigger AS
$$
BEGIN
    INSERT INTO land_feature_linestring.updates(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION land_feature_linestring.refresh() RETURNS trigger AS
$$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh land_feature_linestring';

    -- Analyze tracking and source tables before performing update
    ANALYZE land_feature_linestring.osm_ids;
    ANALYZE land_feature_linestring;

    PERFORM update_land_feature_linestring(false);
    -- noinspection SqlWithoutWhere
    DELETE FROM land_feature_linestring.osm_ids;
    -- noinspection SqlWithoutWhere
    DELETE FROM land_feature_linestring.updates;

    RAISE LOG 'Refresh land_feature_linestring done in %', age(clock_timestamp(), t);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_store
    AFTER INSERT OR UPDATE
    ON land_feature_linestring
    FOR EACH ROW
    WHEN (pg_trigger_depth() < 1)
EXECUTE PROCEDURE land_feature_linestring.store();

CREATE TRIGGER trigger_flag
    AFTER INSERT OR UPDATE
    ON land_feature_linestring
    FOR EACH STATEMENT
    WHEN (pg_trigger_depth() < 1)
EXECUTE PROCEDURE land_feature_linestring.flag();

CREATE CONSTRAINT TRIGGER trigger_refresh
    AFTER INSERT
    ON land_feature_linestring.updates
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE land_feature_linestring.refresh();
