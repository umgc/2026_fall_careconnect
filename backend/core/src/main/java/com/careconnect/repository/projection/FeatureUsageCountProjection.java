package com.careconnect.repository.projection;

/** Native-query projection for feature_use counts. */
public interface FeatureUsageCountProjection {

  String getFeature();

  Number getCount();
}
