# Save boundary

Both runtimes use the private `data\Pal\Saved\SaveGames` boundary. Switching
runtimes requires the runtime mutex, a save operation, and a snapshot according
to the selected workflow. Do not manually copy or delete save files while a
runtime is active.

Static integrity checks and an archive do not prove a successful restore. A
real restore requires an approved maintenance window, a recovery path, and a
post-restore health and save-integrity check.
