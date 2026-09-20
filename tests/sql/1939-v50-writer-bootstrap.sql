\set ON_ERROR_STOP on
INSERT INTO public.source(id,titel,udgave,slags)
VALUES(3,'Danmarks Adels Aarbog','1939','DAA-udgave') ON CONFLICT(id) DO NOTHING;
INSERT INTO auth.users(id,email)
VALUES('11111111-1111-4111-8111-111111111111','writer-ci@example.invalid') ON CONFLICT(id) DO NOTHING;
INSERT INTO public.profiles(id,email,rolle,navn)
VALUES('11111111-1111-4111-8111-111111111111','writer-ci@example.invalid','redaktion','Writer CI')
ON CONFLICT(id) DO UPDATE SET rolle='redaktion',navn='Writer CI';
