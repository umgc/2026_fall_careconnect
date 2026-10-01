package com.careconnect.model.invoice;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class CheckPayableTo {
    private String name;
    private String address;
    private String reference;
}