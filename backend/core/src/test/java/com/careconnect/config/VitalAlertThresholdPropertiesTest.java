package com.careconnect.config;

import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.context.properties.source.ConfigurationPropertySources;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.StandardEnvironment;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;

class VitalAlertThresholdPropertiesTest {

    @Test
    void bindsDefaultPolicyValues() {
        VitalAlertThresholdProperties properties = bindFrom(Map.ofEntries(
                Map.entry("careconnect.alerts.vitals.heart-rate.low-max", "60.0"),
                Map.entry("careconnect.alerts.vitals.heart-rate.high-min", "100.0"),
                Map.entry("careconnect.alerts.vitals.heart-rate.critical-min", "120.0"),
                Map.entry("careconnect.alerts.vitals.spo2.high-max", "95.0"),
                Map.entry("careconnect.alerts.vitals.spo2.critical-max", "90.0"),
                Map.entry("careconnect.alerts.vitals.blood-pressure.systolic.low-max", "90"),
                Map.entry("careconnect.alerts.vitals.blood-pressure.systolic.high-min", "140"),
                Map.entry("careconnect.alerts.vitals.blood-pressure.systolic.critical-min", "180"),
                Map.entry("careconnect.alerts.vitals.blood-pressure.diastolic.low-max", "60"),
                Map.entry("careconnect.alerts.vitals.blood-pressure.diastolic.high-min", "90"),
                Map.entry("careconnect.alerts.vitals.blood-pressure.diastolic.critical-min", "110")
        ));

        assertEquals(60.0, properties.getHeartRate().getLowMax());
        assertEquals(100.0, properties.getHeartRate().getHighMin());
        assertEquals(120.0, properties.getHeartRate().getCriticalMin());
        assertEquals(95.0, properties.getSpo2().getHighMax());
        assertEquals(90.0, properties.getSpo2().getCriticalMax());
        assertEquals(90, properties.getBloodPressure().getSystolic().getLowMax());
        assertEquals(140, properties.getBloodPressure().getSystolic().getHighMin());
        assertEquals(180, properties.getBloodPressure().getSystolic().getCriticalMin());
        assertEquals(60, properties.getBloodPressure().getDiastolic().getLowMax());
        assertEquals(90, properties.getBloodPressure().getDiastolic().getHighMin());
        assertEquals(110, properties.getBloodPressure().getDiastolic().getCriticalMin());
    }

    @Test
    void profileSpecificOverridesCanChangeThresholds() {
        VitalAlertThresholdProperties properties = bindFrom(Map.of(
                "careconnect.alerts.vitals.heart-rate.high-min", "105.0",
                "careconnect.alerts.vitals.heart-rate.critical-min", "130.0",
                "careconnect.alerts.vitals.spo2.high-max", "94.0"
        ));

        assertEquals(105.0, properties.getHeartRate().getHighMin());
        assertEquals(130.0, properties.getHeartRate().getCriticalMin());
        assertEquals(94.0, properties.getSpo2().getHighMax());
    }

    private VitalAlertThresholdProperties bindFrom(Map<String, Object> sourceValues) {
        ConfigurableEnvironment environment = new StandardEnvironment();
        environment.getPropertySources().addFirst(new MapPropertySource("test", sourceValues));
        Binder binder = new Binder(ConfigurationPropertySources.from(environment.getPropertySources()));
        return binder.bind("careconnect.alerts.vitals", VitalAlertThresholdProperties.class)
                .orElseGet(VitalAlertThresholdProperties::new);
    }
}
