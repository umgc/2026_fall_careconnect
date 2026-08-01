package com.careconnect.repository.projection;

/** Native-query projection for daily feature_use counts. */
public interface DailyFeatureCountProjection {

  String getDay();

  Number getCount();
}
