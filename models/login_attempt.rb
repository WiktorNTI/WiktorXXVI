module LoginAttempt
  COOLDOWN_WINDOW   = 15 * 60  # 15 minutes in seconds
  MAX_FAILURES      = 5        # Block after this many failed attempts in the window

  # Logs a login attempt (success or failure).
  def self.log!(db, username, success)
    db.execute(
      'INSERT INTO login_attempts (username, attempted_at, success) VALUES (?, ?, ?)',
      [username, Time.now.to_i, success ? 1 : 0]
    )
  end

  # Returns true if the username is currently locked out due to too many failures.
  def self.locked_out?(db, username)
    since = Time.now.to_i - COOLDOWN_WINDOW
    failures = db.get_first_value(
      'SELECT COUNT(*) FROM login_attempts WHERE username = ? AND attempted_at >= ? AND success = 0',
      [username, since]
    ).to_i
    failures >= MAX_FAILURES
  end

  # Returns how many seconds remain in the cooldown, or 0 if not locked out.
  def self.cooldown_seconds(db, username)
    since = Time.now.to_i - COOLDOWN_WINDOW
    oldest_failure = db.get_first_value(
      'SELECT attempted_at FROM login_attempts WHERE username = ? AND attempted_at >= ? AND success = 0 ORDER BY attempted_at ASC LIMIT 1',
      [username, since]
    )
    return 0 unless oldest_failure
    remaining = (oldest_failure.to_i + COOLDOWN_WINDOW) - Time.now.to_i
    [remaining, 0].max
  end
end
