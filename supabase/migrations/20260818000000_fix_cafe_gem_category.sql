-- The one real gem left in saved_gems after the full wipe ("cafe", id
-- 3bccc225-a0b4-43fe-83b5-5af9403f5f10) is mistagged category='hiking' —
-- confirmed via the live table (fetched read-only via the REST API): a plain
-- data-entry error, not a code mapping bug (GemRepository/GemProvider read
-- the category column straight through with no transform). A cafe has no
-- honest fit among Gem.categories (hiking, camping, viewpoint, food, temple,
-- cave, coastal, nature); 'food' is the closest real category. gem_location
-- is also null, which is a separate, likely cause of it always falling back
-- out of the Add Stop sheet's location filter — set it to Ho Chi Minh City
-- since that's this trip's destination and the only place this gem is
-- currently used from.
update public.saved_gems
set category = 'food',
    gem_location = 'Ho Chi Minh City, Vietnam'
where id = '3bccc225-a0b4-43fe-83b5-5af9403f5f10';
