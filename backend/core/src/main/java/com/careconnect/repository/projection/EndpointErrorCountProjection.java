package com.careconnect.repository.projection;

/** Native-query projection for error counts by endpoint bucket. */
public interface EndpointErrorCountProjection {

  String getEndpoint();

  long getCount();
}
