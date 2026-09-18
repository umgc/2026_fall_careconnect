package com.careconnect.model.invoice;


import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;

import java.util.List;

@Builder
@Data
@AllArgsConstructor
public class PaymentReferences {
    private String paymentLink;
    private String qrCodeUrl;
    private String notes;
    private List<String> supportedMethods;
}