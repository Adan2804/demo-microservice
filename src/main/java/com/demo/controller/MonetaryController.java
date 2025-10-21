package com.demo.controller;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/demo")
public class MonetaryController {

    @Value("${APP_VERSION:v-1-0-0}")
    private String appVersion;

    @Value("${TARGET_URI:}")
    private String targetUri;

    @Value("${spring.application.name:demo-microservice}")
    private String applicationName;

    @GetMapping("/monetary")
    public ResponseEntity<Map<String, Object>> getMonetaryInfo(
            @RequestHeader(value = "X-Request-ID", required = false) String requestId,
            @RequestHeader(value = "X-Correlation-ID", required = false) String correlationId) {
        
        // Generar IDs si no vienen en headers
        if (requestId == null) {
            requestId = UUID.randomUUID().toString();
        }
        if (correlationId == null) {
            correlationId = UUID.randomUUID().toString();
        }

        Map<String, Object> response = new HashMap<>();
        response.put("version", appVersion);
        response.put("service", applicationName);
        response.put("endpoint", "/demo/monetary");
        response.put("timestamp", Instant.now().toString());
        response.put("target_uri", targetUri);
        response.put("status", "active");
        response.put("request_id", requestId);
        response.put("correlation_id", correlationId);
        
        // Datos monetarios simulados
        Map<String, Object> monetaryData = new HashMap<>();
        monetaryData.put("currency", "USD");
        monetaryData.put("exchange_rate", 1.0);
        monetaryData.put("last_updated", Instant.now().toString());
        monetaryData.put("provider", "demo-service");
        response.put("monetary_info", monetaryData);

        // Headers de respuesta
        HttpHeaders headers = new HttpHeaders();
        headers.add("X-App-Version", appVersion);
        headers.add("X-Service-Name", applicationName);
        headers.add("X-Build-Info", "ArgoCD-Managed");
        headers.add("X-Request-ID", requestId);
        headers.add("X-Correlation-ID", correlationId);
        headers.add("X-Response-Time", String.valueOf(System.currentTimeMillis()));

        return ResponseEntity.ok()
                .headers(headers)
                .body(response);
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> health() {
        Map<String, Object> health = new HashMap<>();
        health.put("status", "UP");
        health.put("version", appVersion);
        health.put("service", applicationName);
        health.put("timestamp", Instant.now().toString());
        
        HttpHeaders headers = new HttpHeaders();
        headers.add("X-App-Version", appVersion);
        
        return ResponseEntity.ok()
                .headers(headers)
                .body(health);
    }

    @GetMapping("/info")
    public ResponseEntity<Map<String, Object>> info() {
        Map<String, Object> info = new HashMap<>();
        info.put("app", applicationName);
        info.put("version", appVersion);
        info.put("target_uri", targetUri);
        info.put("java_version", System.getProperty("java.version"));
        info.put("spring_profiles", System.getProperty("spring.profiles.active", "default"));
        info.put("build_timestamp", Instant.now().toString());
        
        // Información del sistema
        Map<String, Object> systemInfo = new HashMap<>();
        systemInfo.put("available_processors", Runtime.getRuntime().availableProcessors());
        systemInfo.put("max_memory", Runtime.getRuntime().maxMemory());
        systemInfo.put("total_memory", Runtime.getRuntime().totalMemory());
        systemInfo.put("free_memory", Runtime.getRuntime().freeMemory());
        info.put("system", systemInfo);
        
        HttpHeaders headers = new HttpHeaders();
        headers.add("X-App-Version", appVersion);
        
        return ResponseEntity.ok()
                .headers(headers)
                .body(info);
    }
}