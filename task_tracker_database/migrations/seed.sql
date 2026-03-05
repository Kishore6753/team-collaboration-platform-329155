-- Optional seed data for local/dev.
-- This is only executed when RUN_SEED=true in migrations/run_migrations.sh.
-- It is designed to be idempotent.

-- Demo user
INSERT INTO public.users (email, password_hash, name)
VALUES ('demo@example.com', '$2b$10$REPLACE_WITH_REAL_HASH', 'Demo User')
ON CONFLICT (email) DO NOTHING;

-- Demo project
WITH u AS (
  SELECT id FROM public.users WHERE email='demo@example.com' LIMIT 1
),
p AS (
  INSERT INTO public.projects (name, description, created_by)
  SELECT 'Demo Project', 'Seeded project for demo/testing', u.id
  FROM u
  ON CONFLICT DO NOTHING
  RETURNING id
)
INSERT INTO public.project_memberships(project_id, user_id, role)
SELECT pr.id, u.id, 'owner'
FROM (SELECT id FROM public.projects WHERE name='Demo Project' LIMIT 1) pr
JOIN u ON true
ON CONFLICT DO NOTHING;

-- Demo task
WITH u AS (
  SELECT id FROM public.users WHERE email='demo@example.com' LIMIT 1
),
p AS (
  SELECT id FROM public.projects WHERE name='Demo Project' LIMIT 1
)
INSERT INTO public.tasks (project_id, title, description, status, priority, created_by, assigned_to)
SELECT p.id, 'Seeded Task', 'This task was created by seed.sql', 'todo', 'medium', u.id, u.id
FROM u, p
ON CONFLICT DO NOTHING;
