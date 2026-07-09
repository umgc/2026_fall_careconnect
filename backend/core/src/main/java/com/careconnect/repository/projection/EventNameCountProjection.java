package com.careconnect.repository.projection;

/** Native-query projection for event name counts. */
public interface EventNameCountProjection {

  String getEventName();

  long getCount();
}
