INSERT INTO app_user (user_id, username, email, password_hash, date_joined)
VALUES
  (1, 'alex_rivera', 'alex.rivera@example.com', 'demo-placeholder', '2025-08-03'),
  (2, 'maya_chen', 'maya.chen@example.com', 'demo-placeholder', '2025-10-01'),
  (3, 'jordan_blake', 'jordan.blake@example.com', 'demo-placeholder', '2024-09-01'),
  (4, 'sam_patel', 'sam.patel@example.com', 'demo-placeholder', '2023-01-10');

-- playlist shells only (no hard-coded song ids from the old hand catalog)
INSERT INTO playlist (playlist_id, user_id, playlist_name, description)
VALUES
  (1, 1, 'Morning Coffee', 'Easy songs to start the day'),
  (2, 1, 'Road Trip', 'Windows down'),
  (3, 1, 'Sunday Acoustic', NULL),
  (4, 2, 'Gym Hype', 'Lift heavy'),
  (5, 2, 'Late Night Drive', NULL),
  (6, 2, 'Throwbacks', 'Songs from high school'),
  (7, 3, 'Classic Rock', NULL),
  (8, 3, 'Mosh Pit', NULL),
  (9, 3, 'Garage Band Practice', 'Songs we are learning'),
  (10, 4, 'Deep Focus', 'For studying'),
  (11, 4, 'Rainy Day Jazz', NULL),
  (12, 4, 'Dance Floor', NULL);

INSERT INTO playlist_collaborator (playlist_id, user_id)
VALUES
  (2, 2),
  (4, 3),
  (12, 1);
