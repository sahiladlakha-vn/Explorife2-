-- Anonymous sign-ins (Supabase Auth "Skip for now" guest flow) create an
-- auth.users row with a NULL email. handle_new_user()'s previous COALESCE
-- chain bottomed out at split_part(NEW.email, '@', 1), which returns NULL
-- for a NULL email — and profiles.name is NOT NULL, so every anonymous
-- signup failed the INSERT and GoTrue surfaced it as a generic 500
-- ("Database error creating anonymous user"). Add a final 'Guest' fallback
-- (matching the client-side AuthProvider naming for anonymous sessions) so
-- the trigger always has a non-null value to write, whether or not a real
-- email is present.
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.profiles (id, display_name, avatar_url, name)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'display_name',
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      NULLIF(split_part(NEW.email, '@', 1), ''),
      'Guest'
    ),
    COALESCE(
      NEW.raw_user_meta_data->>'avatar_url',
      NEW.raw_user_meta_data->>'picture'
    ),
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      NULLIF(split_part(NEW.email, '@', 1), ''),
      'Guest'
    )
  )
  ON CONFLICT (id) DO UPDATE SET
    display_name = COALESCE(EXCLUDED.display_name, profiles.display_name),
    avatar_url   = COALESCE(EXCLUDED.avatar_url,   profiles.avatar_url),
    name         = COALESCE(EXCLUDED.name,         profiles.name),
    updated_at   = now();
  RETURN NEW;
END;
$function$;
