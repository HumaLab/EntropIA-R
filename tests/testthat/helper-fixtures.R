# Fixture helpers -----------------------------------------------------------
#
# Test fixtures live in tests/testthat/fixtures/ and are generated
# deterministically by data-raw/make_fixtures.R. Tests never read from
# data-test/entropia.sqlite (reference corpus only).
#
# Helpers provided here (implemented with the fixture infrastructure task):
# - ent_fixture(name): path to a writable temp copy of fixture `name`
# - ent_connect_fixture(name): entropia_connect() on a temp copy
#
# Fixture inventory (planned): mini, full, legacy-pre0019, legacy-seconds,
# unknown-version, corrupt, notsqlite.
