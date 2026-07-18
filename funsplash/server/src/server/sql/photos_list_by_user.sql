SELECT *
FROM photos
WHERE creator = $1
AND show_on_profile = true;
