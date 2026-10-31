package com.careconnect.config;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class SchemaPatchLedgerSplitCoverageTest {

    @Test
    void splitsAroundCommentsQuotesAndDollarBodies() {
        String script = "-- leading comment\n"
                + "CREATE TABLE \"we\"\"ird\" (id INT); /* block ; comment */\n"
                + "INSERT INTO t VALUES ('it''s; fine');\n"
                + "CREATE FUNCTION f() RETURNS void AS $fn$ BEGIN PERFORM 1; END; $fn$ LANGUAGE plpgsql;\n"
                + "SELECT $1, $$x;y$$;\n"
                + "SELECT 'unterminated";
        List<String> statements = SchemaPatchLedger.splitPostgresStatements(script);
        assertThat(statements).hasSizeGreaterThanOrEqualTo(5);
        assertThat(SchemaPatchLedger.splitPostgresStatements("SELECT \"a")).hasSize(1);
        assertThat(SchemaPatchLedger.splitPostgresStatements("SELECT 1 -- trailing")).hasSize(1);
    }

    @Test
    void rejectsUnterminatedBlocks() {
        assertThatThrownBy(() -> SchemaPatchLedger.splitPostgresStatements("SELECT 1; /* open"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> SchemaPatchLedger.splitPostgresStatements("SELECT $tag$ body"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
