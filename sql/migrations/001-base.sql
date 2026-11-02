-- Starts the hotel from Arcturus' base database (loaded once by deploy/setup.sh): removes Habbo's
-- furni and catalogue (ours come from sql/furni.sql, built on every deploy) and sets the server
-- up for Bobba Hotel.
DELETE FROM items;
DELETE FROM catalog_items;
DELETE FROM catalog_pages;
DELETE FROM items_base WHERE id < 10000 AND id NOT IN (9901, 9902, 9903);
DELETE FROM catalog_club_offers;
DELETE FROM rooms WHERE id < 100;

INSERT INTO emulator_settings (`key`, value) VALUES
  ('console.mode', '0'),
  -- Players' real addresses come from the web server in front (Caddy) in this header.
  ('ws.nitro.ip.header', 'X-Forwarded-For'),
  ('ws.nitro.host', '127.0.0.1'),
  ('ws.nitro.port', '2096'),
  ('hotel.welcome.alert.enabled', '0'),
  ('hotel.users.clothingvalidation.onlogin', '0'),
  ('hotel.users.clothingvalidation.onchangelooks', '0'),
  ('hotel.users.clothingvalidation.onhcexpired', '0'),
  ('hotel.users.clothingvalidation.onmimic', '0'),
  ('hotel.users.clothingvalidation.onmannequin', '0'),
  ('hotel.users.clothingvalidation.onfballgate', '0')
ON DUPLICATE KEY UPDATE value = VALUES(value);
