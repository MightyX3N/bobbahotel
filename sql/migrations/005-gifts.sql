-- Gifts: the hotel's gift parcel (furni bobba_gift, built from the furni list) is the wrapping for
-- every gift bought in the catalogue, and the welcome gift new players find in their room.
DELETE FROM gift_wrappers;
INSERT INTO gift_wrappers (sprite_id, item_id, type) VALUES (10400, 10400, 'gift'), (10400, 10400, 'wrapper');
