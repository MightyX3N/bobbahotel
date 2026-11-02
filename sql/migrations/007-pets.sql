-- Pets, the Habbo way: cats (Habbo's pet type 1) in three colours (races 0-2: ginger, black, grey),
-- bought in the catalogue; any pet eats from the food bowl and drinks from the water bowl.
DELETE FROM pet_breeds WHERE race = 1;
INSERT INTO pet_breeds (race, color_one, color_two, has_color_one, has_color_two) VALUES (1,0,0,'1','0'), (1,1,1,'1','0'), (1,2,2,'1','0');
DELETE FROM pet_items WHERE item_id IN (10435, 10436);
INSERT INTO pet_items (pet_id, item_id) VALUES (-1, 10435), (-1, 10436);
DELETE FROM catalog_items WHERE page_id = 9150;
DELETE FROM catalog_pages WHERE id = 9150;
INSERT INTO catalog_pages (id,parent_id,caption_save,caption,page_layout,icon_image,min_rank,order_num,visible,enabled,page_headline,page_teaser,page_text1,page_text2,page_text_details)
VALUES (9150,-1,'pets','Pets','pets',9150,1,4,'1','1','','','Adopt a cat! Pick a colour and a name.','','Cats follow you around, sit and lie down, and eat from a pet food bowl.');
INSERT INTO catalog_items (item_ids,page_id,catalog_name,cost_credits,cost_points,points_type,amount,order_number,offer_id)
VALUES ('50001',9150,'a0 pet1',20,0,0,1,1,-1);
