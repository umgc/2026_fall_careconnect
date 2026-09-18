package com.careconnect.controller;
import org.springframework.web.bind.annotation.*;

@RestController
public class EHRController{

    public void fetchPatient(){}

    public void fetchCoverage(){}


    public void fetchVisits(){}

    public void fetchEverything(){
        fetchPatient();
        fetchCoverage();
        fetchVisits();
    }

}