package com.weftline;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class WeftlineApplication {

    public static void main(String[] args) {
        SpringApplication.run(WeftlineApplication.class, args);
    }
}