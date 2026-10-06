package com.pkreference.backend.store;

import org.springframework.boot.test.autoconfigure.jdbc.JdbcTest;
import org.springframework.context.annotation.Import;

/** The store's tests on H2. */
@JdbcTest
@Import(TeamStore.class)
class TeamStoreTest extends TeamStoreTestBase {}
