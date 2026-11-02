-- The Welcome Lounge: the public room new players start in (room 100, owned by the hotel).
UPDATE users SET username='Bobba', look='hd-101.hr-101.ch-101.lg-101.sh-101', motto='Welcome to Bobba Hotel!' WHERE id=1;
DELETE FROM room_models WHERE name='bobba_lobby';
INSERT INTO room_models (name,door_x,door_y,door_dir,heightmap,public_items,club_only) VALUES ('bobba_lobby',0,7,2,REPLACE('xxxxxxxxxxx\rx0000000000\rx0000000000\rx0000000000\rx0000000000\rx0000000000\rx0000000000\r00000000000\rx0000000000','\\r',CHAR(13)),'','0');
DELETE FROM items WHERE room_id=100; DELETE FROM rooms WHERE id=100;
INSERT INTO rooms (id,owner_id,owner_name,name,description,model,state,users_max,paper_floor,paper_wall,paper_landscape,thickness_wall,wall_height,thickness_floor,moodlight_data,tags,is_public,category) VALUES (100,1,'Bobba','Welcome Lounge','Say hi to everyone!','bobba_lobby','open',50,'0.0','0.0','0.0',0,-1,0,'','','1',1);
INSERT INTO items (user_id,room_id,item_id,wall_pos,x,y,z,rot,extra_data) VALUES (1,100,10060,'',4,4,0,0,'0'),(1,100,10320,'',3,2,0,4,'0'),(1,100,10307,'',4,4,0,0,'0'),(1,100,10314,'',2,5,0,2,'0'),(1,100,10245,'',1,1,0,0,'0'),(1,100,10114,'',2,1,0,0,'0'),(1,100,10246,'',7,1,0,0,'0'),(1,100,10300,'',9,1,0,4,'0'),(1,100,10182,'',6,2,0,0,'0'),(1,100,10103,'',1,6,0,2,'0'),(1,100,10351,'',8,5,0,0,'0'),(1,100,10065,'',7,5,0,2,'0'),(1,100,10065,'',9,5,0,6,'0'),(1,100,10065,'',8,4,0,4,'0'),(1,100,10188,'',10,8,0,0,'0'),(1,100,10390,':w=4,0 l=8,15 r',0,0,0,0,'0'),(1,100,10231,':w=0,3 l=8,20 l',0,0,0,0,'0'),(1,100,10376,':w=8,0 l=8,15 r',0,0,0,0,'0');
UPDATE navigator_publiccats SET name='Bobba Hotel', visible='1' WHERE id=1;
UPDATE navigator_publiccats SET visible='0' WHERE id<>1;
DELETE FROM navigator_publics WHERE room_id=100;
INSERT INTO navigator_publics (public_cat_id, room_id, visible) VALUES (1, 100, '1');
