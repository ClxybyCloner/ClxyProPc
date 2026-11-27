package service

import (
	"testing"

	"github.com/ClxybyCloner/ClxyProPc/core/internal/psiphon"
)

func TestPsiphonSettingsRoundTrip(t *testing.T) {
	d := &Daemon{}
	if enabled, region := d.psiphonSettings(); enabled || region != "" {
		t.Errorf("default settings = %v %q, want false \"\"", enabled, region)
	}
	if err := d.setPsiphonSettings(true, "de"); err != nil {
		t.Fatal(err)
	}
	if enabled, region := d.psiphonSettings(); !enabled || region != "DE" {
		t.Errorf("settings = %v %q, want true \"DE\"", enabled, region)
	}
	// A bad region is rejected and the previous settings stay.
	if err := d.setPsiphonSettings(true, "DEU"); err == nil {
		t.Error("setPsiphonSettings accepted a three-letter region")
	}
	if enabled, region := d.psiphonSettings(); !enabled || region != "DE" {
		t.Errorf("after bad set: settings = %v %q, want true \"DE\"", enabled, region)
	}
	if err := d.setPsiphonSettings(false, ""); err != nil {
		t.Fatal(err)
	}
	if enabled, region := d.psiphonSettings(); enabled || region != "" {
		t.Errorf("settings = %v %q, want false \"\"", enabled, region)
	}
}

func TestParseEgress(t *testing.T) {
	ip, place, code, err := parseEgress([]byte(`{"status":"success","query":"194.187.251.170","country":"Belgium","countryCode":"BE","city":"Brussels"}`))
	if err != nil {
		t.Fatal(err)
	}
	if ip != "194.187.251.170" || place != "Brussels, Belgium" || code != "BE" {
		t.Errorf("parseEgress = %q %q %q", ip, place, code)
	}
	// No city: the place is just the country.
	if _, place, _, err := parseEgress([]byte(`{"status":"success","query":"1.2.3.4","country":"Germany","countryCode":"de","city":""}`)); err != nil || place != "Germany" {
		t.Errorf("parseEgress no-city = %q, %v", place, err)
	}
	// A failed lookup is an error, not an empty answer.
	if _, _, _, err := parseEgress([]byte(`{"status":"fail","message":"reserved range"}`)); err == nil {
		t.Error("parseEgress accepted a failed lookup")
	}
}

func TestPsiphonStatusShape(t *testing.T) {
	e := &proxyEngine{psiphonEnabled: true, psiphonRegion: "US"}
	if st := e.psiphonStatus(); st != nil {
		t.Error("psiphonStatus without a sidecar should be nil")
	}
	// No sidecar (a Firefox engine): nothing to wait for.
	if !e.psiphonReady() {
		t.Error("psiphonReady should be true with no sidecar")
	}
	// Exit disabled: ready at once.
	e.psiphonEnabled = false
	if !e.psiphonReady() {
		t.Error("psiphonReady should be true when the exit is disabled")
	}
	// Exit enabled with a sidecar that never started: not ready.
	e.psiphonEnabled = true
	e.psiphon = psiphon.NewProcess(t.TempDir())
	if e.psiphonReady() {
		t.Error("psiphonReady should be false while the exit is not running")
	}
	if st := e.psiphonStatus(); st == nil || !st.Enabled || st.Region != "US" || st.Running {
		t.Errorf("psiphonStatus = %+v", st)
	}
}
