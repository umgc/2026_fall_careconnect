package com.careconnect.model;

import lombok.*;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ActionLinks {
    private String track;
    private String deliveryInstructions;
    private String scheduleRedelivery;
    private String dashboard;

    public static ActionLinks defaults(String trackUrl) {
        return ActionLinks.builder()
                .track(trackUrl)
                .deliveryInstructions("https://www.usps.com/manage/package-intercept.htm")
                .scheduleRedelivery("https://tools.usps.com/redelivery.htm")
                .dashboard("https://informeddelivery.usps.com/box/dashboard")
                .build();
    }
}
