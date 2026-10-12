package com.pkreference.backend;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.context.annotation.Bean;
import org.springframework.scheduling.annotation.EnableScheduling;

import java.time.Clock;

/**
 * The program's entry point, and the root of everything Spring builds.
 *
 * <p>How Spring starts this server: {@code main} hands this class to {@code SpringApplication.run},
 * which creates the "application context", the container that makes one object (a "bean") of each
 * class below and passes each the other beans its constructor asks for. Nothing in this project
 * calls {@code new} on a controller, a repository or a Kafka listener: Spring does, in dependency
 * order.
 *
 * <p>The three annotations:
 *
 * <ul>
 * <li>{@code @SpringBootApplication} is three in one. {@code @Configuration}: this class may
 *     declare beans with {@code @Bean} methods. {@code @ComponentScan}: look through this package
 *     and every package under it for classes marked {@code @Component}, {@code @Service},
 *     {@code @Repository}, {@code @RestController} or {@code @Configuration}, and make a bean of
 *     each. {@code @EnableAutoConfiguration}: look at what's on the classpath (Tomcat, Kafka, a
 *     JDBC driver, Flyway) and configure it from application.yml, which is why there is no code
 *     here that opens a database connection or creates a Kafka producer.
 * <li>{@code @ConfigurationPropertiesScan} finds the {@code @ConfigurationProperties} records
 *     (LimitlessProperties, SmogonProperties, ApiAuthProperties) and fills them from
 *     application.yml and environment variables.
 * <li>{@code @EnableScheduling} switches on {@code @Scheduled} methods: without it,
 *     EventDiscovery's and LadderDiscovery's polls would never run.
 * </ul>
 *
 * <p>Start-up, roughly in the order the logs show: Flyway runs the SQL migrations, the topics in
 * Topics are created on the broker, the Kafka listeners subscribe, Tomcat starts listening, and
 * after their initial delays the two scheduled polls begin.
 */
@SpringBootApplication
@ConfigurationPropertiesScan
@EnableScheduling
public class BackendApplication {
    /**
     * Starts Spring Boot: builds the application context and starts the embedded Tomcat web server
     * on port 8080. It returns once the server is up; the server's own threads keep the program
     * running. {@code args} are the command line's, which can override any setting
     * ({@code --server.port=9090}).
     */
    public static void main(String[] args) {
        SpringApplication.run(BackendApplication.class, args);
    }

    /**
     * The time, as discovery, the fetcher and the insights read it. A {@code @Bean} method's return
     * value becomes a bean: any constructor with a {@code Clock} parameter gets this one object.
     * Asking Spring for the clock, rather than calling {@code Instant.now()}, is what lets a test
     * put a fixed or movable clock in its place and check behavior at an exact moment.
     */
    @Bean
    Clock clock() {
        return Clock.systemUTC();
    }
}
