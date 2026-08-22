# RLS by google_user_id with phone as business key

With Google OAuth as the anti-fake gate but phone as the canonical Customer key (`CONTEXT.md`), RLS cannot rely on phone alone. We link `customers.google_user_id = auth.uid()` and write RLS policies as `customers.google_user_id = auth.uid()` and `orders` via `phone → customers` join. Staff/driver visibility uses a role claim. Chosen over open-anon MVP to keep fake-order resistance from day one. Consequence: every insert must populate `google_user_id`; anon key cannot read/write without a valid Google session.
