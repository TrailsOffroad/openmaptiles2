-- etldoc: osm_land_feature_point -> land_feature_point
-- etldoc: ne_10m_admin_0_countries -> land_feature_point
CREATE OR REPLACE VIEW land_feature_point AS
(
SELECT pp.osm_id,
       pp.geometry,
       pp.name,
       pp.name_en,
       pp.tags,
       pp.ele,
       ne.iso_a2,
       pp.wikipedia
FROM land_feature_point pp, ne_10m_admin_0_countries ne
WHERE ST_Intersects(pp.geometry, ne.geometry)
    );



-- etldoc: layer_land_feature[shape=record fillcolor=lightpink,
-- etldoc:     style="rounded,filled", label="layer_land_feature | <z7_> z7+ | <z13_> z13+" ] ;

CREATE OR REPLACE FUNCTION layer_land_feature(bbox geometry,
                                               zoom_level integer,
                                               pixel_width numeric)
    RETURNS TABLE
            (
                osm_id          bigint,
                geometry        geometry,
                name            text,
                name_en         text,
                class           text,
                tags            hstore,
                "rank"          int
            )
AS
$$
SELECT
    -- etldoc: land_feature_point -> layer_land_feature:z10_
    osm_id,
    geometry,
    name,
    name_en,
    tags->'natural' AS class,
    tags,
    rank::int
FROM (
         SELECT osm_id,
                geometry,
                NULLIF(name, '') as name,
                COALESCE(NULLIF(name_en, ''), NULLIF(name, '')) AS name_en,
                tags,
                row_number() OVER (
                    PARTITION BY LabelGrid(geometry, 100 * pixel_width)
                    ORDER BY (
                            (CASE WHEN wikipedia <> '' THEN 10000 ELSE 0 END) +
                            (CASE WHEN name <> '' THEN 10000 ELSE 0 END)
                        ) DESC
                    )::int AS "rank"
         FROM land_feature_point
         WHERE geometry && bbox
           AND NULLIF(name, '') IS NOT NULL
     ) AS ranked_peaks
WHERE zoom_level >= 10

$$ LANGUAGE SQL STABLE
                PARALLEL SAFE;
-- TODO: Check if the above can be made STRICT -- i.e. if pixel_width could be NULL
