package toolkit

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type patientRegistration struct {
	Role      string `json:"role"`
	Name      string `json:"name"`
	Email     string `json:"email"`
	Password  string `json:"password"`
	FirstName string `json:"firstName"`
	LastName  string `json:"lastName"`
	Phone     string `json:"phone"`
	DOB       string `json:"dob"`
	Gender    string `json:"gender"`
}

func (a *App) registerPatient(repoRoot string) error {
	baseURL := backendBaseURL(repoRoot)
	now := time.Now().UTC().Format("20060102150405")
	emailDefault := "testpatient" + now + "@example.com"

	fmt.Fprintln(a.out)
	fmt.Fprintln(a.out, "Register a dev patient")
	fmt.Fprintln(a.out, "This uses the normal application registration API.")
	baseURLInput, err := a.prompt("Backend base URL: ", baseURL)
	if err != nil {
		return err
	}
	email, err := a.prompt("Email: ", emailDefault)
	if err != nil {
		return err
	}
	password, err := a.prompt("Password: ", "TestPassword123!")
	if err != nil {
		return err
	}
	firstName, err := a.prompt("First name: ", "Test")
	if err != nil {
		return err
	}
	lastName, err := a.prompt("Last name: ", "Patient")
	if err != nil {
		return err
	}
	phone, err := a.prompt("Phone: ", "555-0100")
	if err != nil {
		return err
	}
	dob, err := a.prompt("DOB (YYYY-MM-DD): ", "1980-01-01")
	if err != nil {
		return err
	}
	gender, err := a.prompt("Gender: ", "FEMALE")
	if err != nil {
		return err
	}

	payload := patientRegistration{
		Role:      "PATIENT",
		Name:      strings.TrimSpace(firstName + " " + lastName),
		Email:     email,
		Password:  password,
		FirstName: firstName,
		LastName:  lastName,
		Phone:     phone,
		DOB:       dob,
		Gender:    strings.ToUpper(gender),
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	fmt.Fprintf(a.out, "POST %s/v1/api/auth/register\n", strings.TrimRight(baseURLInput, "/"))
	ok, err := a.confirm("Create this patient?", false)
	if err != nil {
		return err
	}
	if !ok {
		fmt.Fprintln(a.out, "Skipped.")
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(baseURLInput, "/")+"/v1/api/auth/register", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	fmt.Fprintf(a.out, "HTTP %d\n", resp.StatusCode)
	if len(respBody) > 0 {
		fmt.Fprintln(a.out, strings.TrimSpace(string(respBody)))
	}
	return nil
}
