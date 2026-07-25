package com.careconnect.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "careconnect.alerts.vitals")
@Getter
@Setter
public class VitalAlertThresholdProperties {

    private HeartRate heartRate = new HeartRate();
    private Spo2 spo2 = new Spo2();
    private BloodPressure bloodPressure = new BloodPressure();

    @Getter
    @Setter
    public static class HeartRate {
        private double lowMax = 60.0;
        private double highMin = 100.0;
        private double criticalMin = 120.0;
    }

    @Getter
    @Setter
    public static class Spo2 {
        private double highMax = 95.0;
        private double criticalMax = 90.0;
    }

    @Getter
    @Setter
    public static class BloodPressure {
        private Thresholds systolic = new Thresholds(90, 140, 180);
        private Thresholds diastolic = new Thresholds(60, 90, 110);
    }

    @Getter
    @Setter
    public static class Thresholds {
        private int lowMax;
        private int highMin;
        private int criticalMin;

        public Thresholds() {
        }

        public Thresholds(int lowMax, int highMin, int criticalMin) {
            this.lowMax = lowMax;
            this.highMin = highMin;
            this.criticalMin = criticalMin;
        }
    }
}
