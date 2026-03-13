import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import sendVerificationEmail from '@salesforce/apex/RegistrationFormController.sendVerificationEmail';
import registerLead from '@salesforce/apex/RegistrationFormController.registerLead';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const RESEND_COOLDOWN_SECONDS = 60;
const OTP_VALIDITY_MS = 60 * 1000; // 60 seconds

export default class RegistrationForm extends LightningElement {
    @track firstName = '';
    @track lastName = '';
    @track email = '';
    @track phone = '';

    @track companyName = '';


    @track otpInput = '';
    @track emailVerified = false;
    @track isSendingCode = false;
    @track isSubmitting = false;

    @track resendTimer = 0;
    timerId;

    countryCode = '+91';
    countryCodeOptions = [
        { label: '+91 India', value: '+91' },
        { label: '+1 United States', value: '+1' },
        { label: '+44 United Kingdom', value: '+44' },
        { label: '+61 Australia', value: '+61' }
    ];

    generatedOtp;
    otpExpiresAt;
    showSuccessScreen = false;

    // ----- Getters -----

    get disableVerifyButton() {
        return !this.generatedOtp || !this.otpInput || this.emailVerified;
    }

    get resendTimerActive() {
        return this.resendTimer > 0;
    }

    // get sendCodeButtonLabel() {
    //     if (!this.generatedOtp) {
    //         return 'Send Code';
    //     }
    //     return this.resendTimerActive ? `Resend in ${this.resendTimer}s` : 'Resend Code';
    // }

    get sendCodeButtonLabel() {
        return this.resendTimerActive ? `Resend in ${this.resendTimer}s` : (this.generatedOtp ? 'Resend Code' : 'Send Code');
    }


    get isEmailFormatValid() {
        const value = (this.email || '').trim();
        return EMAIL_REGEX.test(value);
    }

    get isPhoneValid() {
        const digits = this.getPhoneDigits();
        return digits.length === 10;
    }

    // get isSendCodeDisabled() {
    //     return this.isSendingCode || this.resendTimerActive || !this.isEmailFormatValid;
    // }

    get isSendCodeDisabled() {
        return this.isSendingCode || this.resendTimerActive || this.emailVerified || !this.isEmailFormatValid;
    }


    get isRegisterDisabled() {
        return this.isSubmitting || !this.emailVerified || !this.isPhoneValid;
    }

    disconnectedCallback() {
        this.clearResendTimer();
    }

    // ----- Input handlers -----

    handleInputChange(event) {
        const { name, value } = event.target;

        if (name === 'firstName') {
            this.firstName = value;
        } else if (name === 'lastName') {
            this.lastName = value;
        } else if (name === 'email') {
            this.email = value;
            this.validateEmailField();
        } else if (name === 'phone') {
            this.phone = value;
            this.validatePhoneField();
        }
        else if (name === 'companyName') {
            this.companyName = value;
        }

    }

    handleCountryChange(event) {
        this.countryCode = event.detail.value;
    }

    handleOtpChange(event) {
        this.otpInput = event.target.value;
    }

    handleSendCode() {
        // ✅ Must have required fields before sending OTP
        const emailOk = this.validateEmailField();
        const phoneOk = this.validatePhoneField();

        if (!this.firstName || !this.lastName) {
            this.showToast('Error', 'First Name and Last Name are required.', 'error');
            return;
        }

        if (!emailOk || !phoneOk) {
            return;
        }

        if (this.emailVerified) {
            return; // already verified
        }

        if (this.resendTimerActive) {
            return; // cooldown running
        }

        this.isSendingCode = true;
        this.emailVerified = false;
        this.otpInput = '';

        this.generatedOtp = this.generateOtp();
        this.otpExpiresAt = Date.now() + OTP_VALIDITY_MS;

        sendVerificationEmail({
            email: this.email,
            verificationCode: this.generatedOtp
        })
            .then(() => {
                this.showToast('Success', 'Verification code sent to your email.', 'success');
                this.startResendCountdown();
            })
            .catch((error) => {
                this.generatedOtp = null;
                this.otpExpiresAt = null;
                this.clearResendTimer();
                this.handleApexError(error, 'Failed to send verification code.');
            })
            .finally(() => {
                this.isSendingCode = false;
            });
    }


    handleVerifyCode() {
        if (!this.generatedOtp) {
            this.showToast('Error', 'Please click "Send Code" first.', 'error');
            return;
        }

        if (this.otpExpiresAt && Date.now() > this.otpExpiresAt) {
            this.showToast('Error', 'Verification code has expired. Please resend a new code.', 'error');
            this.generatedOtp = null;
            this.otpExpiresAt = null;
            this.otpInput = '';
            this.emailVerified = false;
            return;
        }

        if (!this.otpInput) {
            this.showToast('Error', 'Please enter the verification code.', 'error');
            return;
        }

        if (this.otpInput === this.generatedOtp) {
            this.emailVerified = true;

            // ✅ STOP timer immediately after verification
            this.clearResendTimer();

            this.showToast('Success', 'Email verified successfully.', 'success');
        } else {

            this.emailVerified = false;
            this.showToast('Error', 'Invalid verification code. Please try again.', 'error');
        }
    }

    // ----- Submit -----

    handleSubmit() {
        const emailOk = this.validateEmailField();
        const phoneOk = this.validatePhoneField();
        if (!emailOk || !phoneOk) {
            return;
        }

        if (!this.emailVerified) {
            this.showToast('Error', 'Please verify your email before registering.', 'error');
            return;
        }

        if (!this.firstName || !this.lastName) {
            this.showToast('Error', 'First Name and Last Name are required.', 'error');
            return;
        }

        this.isSubmitting = true;

        const fullPhone = this.countryCode
            ? `${this.countryCode} ${this.phone}`
            : this.phone;

        const firstName = (this.firstName || '').trim();
        const lastName = (this.lastName || '').trim();

        const payload = {
            firstName: firstName,
            lastName: lastName,
            email: this.email,
            phone: fullPhone,

            companyName:
                (this.companyName && this.companyName.trim())
                    ? this.companyName.trim()
                    : `Self-${firstName} ${lastName}`.trim(),

            companySize: '1-10',
            companyIndustry: 'Other',
            companyWebsite: 'https://www.arelialiving.com',
            companyDescription: 'Arelia Living',
            companyAddress: '123 Main St',
            companyCity: this.companyCity || 'N/A'
        };


        registerLead({ payload })
            .then(() => {
                this.showSuccessScreen = true;
                this.resetForm();
            })
            .catch((error) => {
                this.handleApexError(error, 'Failed to register. Please try again.');
            })
            .finally(() => {
                this.isSubmitting = false;
            });
    }

    handleCloseSuccess() {
        this.showSuccessScreen = false;
    }

    // ----- Validation -----

    validateEmailField() {
        const input = this.template.querySelector('[data-id="emailInput"]');
        if (!input) {
            return false;
        }

        const value = (this.email || '').trim();
        let message = '';

        if (!value) {
            message = 'Email is required.';
        } else if (!EMAIL_REGEX.test(value)) {
            message = 'Enter a valid email address (e.g. name@example.com).';
        }

        input.setCustomValidity(message);
        input.reportValidity();
        return !message;
    }

    validatePhoneField() {
        const input = this.template.querySelector('[data-id="phoneInput"]');
        if (!input) {
            return false;
        }

        const digits = this.getPhoneDigits();
        let message = '';

        if (!digits) {
            message = 'Mobile number is required.';
        } else if (digits.length !== 10) {
            message = 'Enter a 10-digit mobile number.';
        }

        input.setCustomValidity(message);
        input.reportValidity();
        return !message;
    }

    getPhoneDigits() {
        return (this.phone || '').replace(/\D/g, '');
    }

    // ----- Timer -----

    startResendCountdown() {
        this.clearResendTimer();
        this.resendTimer = RESEND_COOLDOWN_SECONDS;

        this.timerId = window.setInterval(() => {
            if (this.resendTimer <= 1) {
                this.clearResendTimer();
            } else {
                this.resendTimer -= 1;
            }
        }, 1000);
    }

    clearResendTimer() {
        if (this.timerId) {
            clearInterval(this.timerId);
            this.timerId = undefined;
        }
        this.resendTimer = 0;
    }

    // ----- Utility -----

    generateOtp() {
        const code = Math.floor(100000 + Math.random() * 900000);
        return String(code);
    }

    resetForm() {
        this.firstName = '';
        this.lastName = '';
        this.email = '';
        this.phone = '';
        this.otpInput = '';
        this.generatedOtp = null;
        this.otpExpiresAt = null;
        this.emailVerified = false;
        this.clearResendTimer();
        this.countryCode = '+91';
        this.companyName = '';
    }

    handleApexError(error, fallbackMessage) {
        let message = fallbackMessage;
        if (error && error.body && error.body.message) {
            message = error.body.message;
        }
        this.showToast('Error', message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}