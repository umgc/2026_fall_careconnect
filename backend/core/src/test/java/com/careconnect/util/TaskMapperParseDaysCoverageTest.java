package com.careconnect.util;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class TaskMapperParseDaysCoverageTest {

    @Test
    void parsesEveryLegacyDayFormat() {
        assertThat(TaskMapper.parseDays(null)).isNull();
        assertThat(TaskMapper.parseDays(" null ")).isNull();
        assertThat(TaskMapper.parseDays("[true,false]")).hasSize(7);
        assertThat(TaskMapper.parseDays("[true,false,true,false,false,true,false,true]")).hasSize(7);
        assertThat(TaskMapper.parseDays("\"[true,false,true,false,false,true,false]\"")).hasSize(7);
        assertThat(TaskMapper.parseDays(
                "[\"SUNDAY\",\"monday\",\"Tue\",\"wed\",\"thu\",\"fri\",\"sat\",\"\",\"bogus\"]"))
                .containsOnly(true);
        List<Boolean> fromMap = TaskMapper.parseDays(
                "{\"sunday\":true,\"monday\":1,\"tuesday\":\"yes\",\"wednesday\":\"no\",\"nope\":true,\"friday\":0}");
        assertThat(fromMap).hasSize(7);
        assertThat(TaskMapper.parseDays("{\"monday\":false}")).isNull();
        assertThat(TaskMapper.parseDays("{}")).isNull();
        assertThat(TaskMapper.parseDays("MON, WED,FRI")).hasSize(7);
        assertThat(TaskMapper.parseDays("garbage text")).isNull();
        assertThat(TaskMapper.parseDays("[]")).isNotNull();
    }
}
