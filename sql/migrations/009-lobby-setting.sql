-- No default rooms and no hotel view: the owners build the rooms in the game and pick one as the
-- lobby on the admin pages (emulator_settings "bobba.lobby"); everyone lands there. New players get
-- their first room from Bobba, the lobby's bot.
DELETE FROM items WHERE room_id IN (100, 102, 103);
DELETE FROM bots WHERE room_id IN (100, 102, 103);
DELETE FROM navigator_publics WHERE room_id IN (100, 102, 103);
DELETE FROM rooms WHERE id IN (100, 102, 103);
DELETE FROM room_models WHERE name IN ('bobba_lobby', 'bobba_casino', 'bobba_city');
UPDATE users SET home_room = 0 WHERE home_room IN (100, 102, 103);
INSERT INTO emulator_settings (`key`, `value`) VALUES ('bobba.lobby', '0') ON DUPLICATE KEY UPDATE `value` = `value`;
