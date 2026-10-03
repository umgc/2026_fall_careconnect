package com.careconnect.service;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.ehr.MedicareService;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.session.SessionRegistry;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.web.authentication.AuthenticationSuccessHandler;
import org.springframework.security.web.context.SecurityContextRepository;
import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;

import java.io.IOException;
import java.time.LocalDateTime;
import java.util.Optional;
import java.util.UUID;


@Service
@Slf4j
public class OAuthHelperService implements AuthenticationSuccessHandler {
    @Autowired
    private UserRepository userRepository;

    @Value("${frontend.base-url}")
    private String frontendBaseUrl; // --- Register new user ---

    @Autowired
    private EhrPatientCrosswalkRepository ehrPatientCrosswalkRepository;

    @Autowired
    private UserRepository userRepo;

    @Autowired
    private MedicareService medicareService;

    @PostMapping("/oauth2/connect")
    public void outgoing(String where, Authentication authentication, HttpSession session, HttpServletResponse response) throws IOException, ServletException {
        Long userId = userRepo.findByEmail(authentication.getName()).orElseThrow().getId();
        if(where.equalsIgnoreCase("medicare")) {

            Long medicareId = medicareService.getId();
            if(medicareId == null){
                medicareService.retrieveId();
                medicareId = medicareService.getId();
            }

            Optional<EhrPatientCrosswalk> crosswalk = ehrPatientCrosswalkRepository.findByPatientIdAndSourceId(userId, medicareId);

            if(crosswalk.isEmpty()){

                String linkToken =  UUID.randomUUID().toString();
                log.info("Crosswalk currently empty! Building with user {} and Session {} Link token: {}",
                        userId, session.getId(), linkToken);

                EhrPatientCrosswalk toadd = new EhrPatientCrosswalk();
                toadd.setLinkToken(linkToken);
                toadd.setSourceId(medicareId);
                toadd.setPatientId(userId);
                ehrPatientCrosswalkRepository.save(toadd);
                session.setAttribute(where, linkToken);
            }

        }
        response.sendRedirect("/oauth2/authorization/" + where);
    }


    public void onAuthenticationSuccess(HttpServletRequest request, HttpServletResponse response, Authentication authentication) throws IOException {
        OAuth2AuthenticationToken oauthToken = (OAuth2AuthenticationToken) authentication;
        log.info("Oauth Success! {}, {}, {} On Session {}", oauthToken.getName(),
                oauthToken.getAuthorizedClientRegistrationId(),
                oauthToken.getPrincipal().getName(),  request.getSession().getId());

        String source = oauthToken.getAuthorizedClientRegistrationId();

        if(source.equals("medicare")){

            String linkToken = request.getSession().getAttribute("medicare").toString();
            log.info("Got link token: {}", linkToken);

            Optional<EhrPatientCrosswalk> crosswalkOpt = ehrPatientCrosswalkRepository.findByLinkToken(linkToken);

            // Turns out they aren't real.
            if(crosswalkOpt.isEmpty()){response.setStatus(HttpServletResponse.SC_UNAUTHORIZED); return;}

            EhrPatientCrosswalk crosswalk = crosswalkOpt.orElseThrow();
            crosswalk.setExternalPatientId(oauthToken.getPrincipal().getName());
            crosswalk.setRefreshToken("");
            crosswalk.setLastLoggedIn(LocalDateTime.now());
            crosswalk.setToken("");
            ehrPatientCrosswalkRepository.save(crosswalk);
            response.sendRedirect(frontendBaseUrl);
        }

    }


}
