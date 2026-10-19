package com.careconnect.model.checkins;

import java.util.Date;

public class CheckIn {

    int id;

    CheckInTemplate template;

    Date dateSubmitted;

    CheckIn(CheckInTemplate inTemplate) {
        template = inTemplate;
    }

    public CheckIn() {
        //This just exists to make the controller stop complaining.
    }


}
