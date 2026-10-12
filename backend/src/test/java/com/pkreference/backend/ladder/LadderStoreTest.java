package com.pkreference.backend.ladder;

import org.springframework.boot.test.autoconfigure.jdbc.JdbcTest;
import org.springframework.context.annotation.Import;

/** The ladder store's tests on H2. */
@JdbcTest
@Import({LadderStore.class, LadderService.class, LadderTestConfig.class})
class LadderStoreTest extends LadderStoreTestBase {}
