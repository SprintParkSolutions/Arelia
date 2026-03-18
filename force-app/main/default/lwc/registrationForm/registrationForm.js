import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import sendVerificationEmail from '@salesforce/apex/RegistrationFormController.sendVerificationEmail';
import registerLead from '@salesforce/apex/RegistrationFormController.registerLead';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const NAME_REGEX = /^[A-Za-z\s]+$/;
const PHONE_REGEX = /^[0-9]{10}$/;
const RESEND_COOLDOWN_SECONDS = 60;
const OTP_VALIDITY_MS = 60 * 1000; // 60 seconds

export default class RegistrationForm extends LightningElement {
    @track firstName = '';
    @track lastName = '';
    @track email = '';
    @track phone = '';
    @track companyName = '';

    @track firstNameError = '';
    @track lastNameError = '';

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

    get sendCodeButtonLabel() {
        return this.resendTimerActive
            ? `Resend in ${this.resendTimer}s`
            : (this.generatedOtp ? 'Resend Code' : 'Send Code');
    }

    get isEmailFormatValid() {
        return EMAIL_REGEX.test((this.email || '').trim());
    }

    get isPhoneValid() {
        return PHONE_REGEX.test((this.phone || '').trim());
    }

    get isSendCodeDisabled() {
        return this.isSendingCode || this.resendTimerActive || this.emailVerified || !this.isEmailFormatValid;
    }

    get isRegisterDisabled() {
        return this.isSubmitting || !this.emailVerified || !this.isPhoneValid || !this.validateNameFields();
    }

    disconnectedCallback() {
        this.clearResendTimer();
    }

    // ----- Input handlers -----
    handleInputChange(event) {
        const { name, value } = event.target;

        if (name === 'firstName') {
            this.firstName = value;
            this.validateFirstName();
        } else if (name === 'lastName') {
            this.lastName = value;
            this.validateLastName();
        } else if (name === 'email') {
            this.email = value;
            this.validateEmailField();
        } else if (name === 'phone') {
            this.phone = value;
            this.validatePhoneField();
        } else if (name === 'companyName') {
            this.companyName = value;
        }
    }

    handleCountryChange(event) {
        this.countryCode = event.detail.value;
    }

    handleOtpChange(event) {
        this.otpInput = event.target.value;
    }

    // ----- OTP send & verify -----
    handleSendCode() {
        const emailOk = this.validateEmailField();
        const phoneOk = this.validatePhoneField();
        const namesOk = this.validateNameFields();

        if (!emailOk || !phoneOk || !namesOk) return;

        if (this.emailVerified || this.resendTimerActive) return;

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
            this.showToast('Error', 'Verification code has expired. Please resend.', 'error');
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
        const namesOk = this.validateNameFields();

        if (!emailOk || !phoneOk || !namesOk) return;
        if (!this.emailVerified) {
            this.showToast('Error', 'Please verify your email before registering.', 'error');
            return;
        }

        this.isSubmitting = true;
        const fullPhone = this.countryCode ? `${this.countryCode} ${this.phone}` : this.phone;

        const payload = {
            firstName: this.firstName.trim(),
            lastName: this.lastName.trim(),
            email: this.email,
            phone: fullPhone,
            companyName: (this.companyName && this.companyName.trim())
                ? this.companyName.trim()
                : `Self-${this.firstName.trim()} ${this.lastName.trim()}`.trim()
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
    validateFirstName() {
        if (!this.firstName || !NAME_REGEX.test(this.firstName)) {
            this.firstNameError = this.firstName
                ? 'First Name cannot contain numbers or special characters.'
                : 'First Name is required.';
            return false;
        }
        this.firstNameError = '';
        return true;
    }

    validateLastName() {
        if (!this.lastName || !NAME_REGEX.test(this.lastName)) {
            this.lastNameError = this.lastName
                ? 'Last Name cannot contain numbers or special characters.'
                : 'Last Name is required.';
            return false;
        }
        this.lastNameError = '';
        return true;
    }

    validateNameFields() {
        const firstValid = this.validateFirstName();
        const lastValid = this.validateLastName();
        return firstValid && lastValid;
    }

    validateEmailField() {
        const input = this.template.querySelector('[data-id="emailInput"]');
        let message = '';
        const value = (this.email || '').trim();

        if (!value) message = 'Email is required.';
        else if (!EMAIL_REGEX.test(value)) message = 'Enter a valid email address (e.g. name@example.com).';

        if (input) {
            input.setCustomValidity(message);
            input.reportValidity();
        }
        return !message;
    }

    validatePhoneField() {
        const input = this.template.querySelector('[data-id="phoneInput"]');
        const value = (this.phone || '').trim();
        let message = '';

        if (!value) message = 'Mobile number is required.';
        else if (!/^[0-9]*$/.test(value)) message = 'Mobile number must contain digits only.';
        else if (!PHONE_REGEX.test(value)) message = 'Enter a valid 10-digit mobile number.';

        if (input) {
            input.setCustomValidity(message);
            input.reportValidity();
        }
        return !message;
    }

    // ----- Timer -----
    startResendCountdown() {
        this.clearResendTimer();
        this.resendTimer = RESEND_COOLDOWN_SECONDS;
        this.timerId = setInterval(() => {
            if (this.resendTimer <= 1) this.clearResendTimer();
            else this.resendTimer -= 1;
        }, 1000);
    }

    clearResendTimer() {
        if (this.timerId) clearInterval(this.timerId);
        this.timerId = undefined;
        this.resendTimer = 0;
    }

    // ----- Utility -----
    generateOtp() {
        return String(Math.floor(100000 + Math.random() * 900000));
    }

    resetForm() {
        this.firstName = '';
        this.lastName = '';
        this.email = '';
        this.phone = '';
        this.companyName = '';
        this.otpInput = '';
        this.firstNameError = '';
        this.lastNameError = '';
        this.generatedOtp = null;
        this.otpExpiresAt = null;
        this.emailVerified = false;
        this.clearResendTimer();
        this.countryCode = '+91';
    }

    handleApexError(error, fallbackMessage) {
        let message = fallbackMessage;
        if (error?.body?.message) message = error.body.message;
        this.showToast('Error', message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}