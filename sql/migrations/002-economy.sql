-- Bobba Hotel economy. Nothing in the game costs real money except club, which donations give
-- (through the website). Club can also be bought in the catalogue with diamonds, at a price that
-- takes a while of playing to earn: diamonds come 5 every 10 minutes (30 an hour) to active
-- players only.
UPDATE catalog_club_offers SET enabled = '0';
DELETE FROM catalog_club_offers WHERE id IN (9001, 9002);
INSERT INTO catalog_club_offers (id, enabled, name, days, credits, points, points_type, type, deal, giftable) VALUES
  (9001, '1', 'BOBBA_CLUB_1_MONTH', 31, 0, 1500, 5, 'HC', '0', '0'),
  (9002, '1', 'BOBBA_CLUB_3_MONTHS', 93, 0, 4000, 5, 'HC', '0', '0');

-- Free currencies, every 10 minutes: credits and duckets 100, diamonds 5. Idle players (and
-- players on the hotel view) don't earn diamonds, so leaving the game open can't farm club.
UPDATE emulator_settings SET value = '1' WHERE `key` IN ('hotel.auto.points.ignore.idled', 'hotel.auto.points.ignore.hotelview');
UPDATE emulator_settings SET value = '5' WHERE `key` = 'hotel.auto.points.amount';
UPDATE emulator_settings SET value = '600' WHERE `key` = 'hotel.auto.points.interval';
-- Club payday (credits back for club members) off, so club isn't pay-to-win.
UPDATE emulator_settings SET value = '0' WHERE `key` = 'subscriptions.hc.payday.enabled';

-- The catalogue page where club is bought.
DELETE FROM catalog_pages WHERE id = 9100;
INSERT INTO catalog_pages (id, parent_id, caption_save, caption, page_layout, icon_color, icon_image, min_rank, order_num, visible, enabled, page_headline, page_teaser, page_text1)
VALUES (9100, -1, 'bobba_club', 'Bobba Club', 'vip_buy', 1, 1, 1, 3, '1', '1', '', '', 'Join Bobba Club with diamonds you earn by playing, or by supporting the hotel.');
