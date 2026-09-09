package com.careconnect.service;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.UserRepository;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.web.authentication.AuthenticationSuccessHandler;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.time.LocalDateTime;


@Service
@Slf4j
public class OAuthHelperService implements AuthenticationSuccessHandler {
    @Autowired
    private UserRepository userRepository;

    @Value("${frontend.base-url}")
    private String frontendBaseUrl; // --- Register new user ---

    //@Autowired
    //private CustomOAuth2UserService customOAuth2UserService;

    @Autowired
    private EhrPatientCrosswalkRepository ehrPatientCrosswalkRepository;

    public void onAuthenticationSuccess(HttpServletRequest request, HttpServletResponse response, Authentication authentication) throws IOException {
        OAuth2AuthenticationToken oauthToken = (OAuth2AuthenticationToken) authentication;
        log.info("Authenticaion Success!");
        log.info(oauthToken.getName());
        log.info(oauthToken.getAuthorizedClientRegistrationId());
        log.info(oauthToken.getPrincipal().getName());
        Authentication currentUserAuth = SecurityContextHolder.getContext().getAuthentication();
        log.info(currentUserAuth.getName());
        User currentUser = userRepository.findByEmail(currentUserAuth.getName()).orElseThrow();
        String source = oauthToken.getAuthorizedClientRegistrationId();

        if(source.equals("medicare")){
            EhrPatientCrosswalk  crosswalk = new EhrPatientCrosswalk();
            crosswalk.setPatientId(currentUser.getId());
            crosswalk.setExternalPatientId(oauthToken.getPrincipal().getName());
            crosswalk.setRefreshToken("");
            crosswalk.setLastLoggedIn(LocalDateTime.now());
            crosswalk.setToken("");
            ehrPatientCrosswalkRepository.save(crosswalk);
            response.sendRedirect(frontendBaseUrl);
        }

    }


}
