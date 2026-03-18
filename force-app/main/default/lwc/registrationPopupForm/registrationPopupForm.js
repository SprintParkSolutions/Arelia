import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import sendVerificationEmail from '@salesforce/apex/RegistrationFormController.sendVerificationEmail';
import registerLead from '@salesforce/apex/RegistrationFormController.registerLead';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const NAME_REGEX = /^[A-Za-z\s]+$/;
const PHONE_REGEX = /^[0-9]{10}$/;
const RESEND_COOLDOWN_SECONDS = 60;
const OTP_VALIDITY_MS = 60 * 1000;

const STEP_DETAILS = 1;
const STEP_VERIFY = 2;

export default class RegistrationPopupForm extends LightningElement {
    @track isOpen = true;
    @track currentStep = STEP_DETAILS;

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
    @track showSuccessScreen = false;

    get isStep1() {
        return this.currentStep === STEP_DETAILS;
    }

    get isStep2() {
        return this.currentStep === STEP_VERIFY;
    }

    get disableVerifyButton() {
        return !this.generatedOtp || !this.otpInput || this.emailVerified;
    }

    get resendTimerActive() {
        return this.resendTimer > 0;
    }

    get sendCodeButtonLabel() {
        return this.resendTimerActive ? `Resend in ${this.resendTimer}s` : 'Resend Code';
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
        return this.isSubmitting || !this.emailVerified || !this.isPhoneValid;
    }

    get step1Class() {
        return this.currentStep === STEP_DETAILS ? 'step-item active' : 'step-item completed';
    }

    get step2Class() {
        return this.currentStep === STEP_VERIFY ? 'step-item active' : 'step-item';
    }

    disconnectedCallback() {
        this.clearResendTimer();
    }

    closeModal() {
        this.isOpen = false;
        this.showSuccessScreen = false;
        this.clearResendTimer();
        this.resetForm();
        this.currentStep = STEP_DETAILS;

        this.dispatchEvent(
            new CustomEvent('closepopup', {
                bubbles: true,
                composed: true
            })
        );
    }

    handleNextFromDetails() {
        const firstOk = this.validateFirstName();
        const lastOk = this.validateLastName();
        const emailOk = this.validateEmailField();
        const phoneOk = this.validatePhoneField();

        if (!firstOk || !lastOk || !emailOk || !phoneOk) {
            return;
        }

        this.currentStep = STEP_VERIFY;

        Promise.resolve().then(() => {
            this.handleSendCode(true);
        });
    }

    handleBackToDetails() {
        this.currentStep = STEP_DETAILS;
        this.generatedOtp = null;
        this.otpExpiresAt = null;
        this.otpInput = '';
        this.emailVerified = false;
        this.clearResendTimer();
    }

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

    handleSendCode(auto = false) {
        if (!this.validateEmailField() || this.emailVerified || (!auto && this.resendTimerActive) || this.isSendingCode) {
            return;
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
            this.clearResendTimer();
            this.showToast('Success', 'Email verified successfully.', 'success');
        } else {
            this.emailVerified = false;
            this.showToast('Error', 'Invalid verification code. Please try again.', 'error');
        }
    }

    handleSubmit() {
        const firstOk = this.validateFirstName();
        const lastOk = this.validateLastName();
        const emailOk = this.validateEmailField();
        const phoneOk = this.validatePhoneField();

        if (!firstOk || !lastOk || !emailOk || !phoneOk) {
            return;
        }

        if (!this.emailVerified) {
            this.showToast('Error', 'Please verify your email before completing registration.', 'error');
            return;
        }

        this.isSubmitting = true;

        const fullPhone = this.countryCode ? `${this.countryCode} ${this.phone}` : this.phone;
        const firstName = (this.firstName || '').trim();
        const lastName = (this.lastName || '').trim();

        const payload = {
            firstName: firstName,
            lastName: lastName,
            email: this.email,
            phone: fullPhone,
            companyName: (this.companyName && this.companyName.trim())
                ? this.companyName.trim()
                : `Self-${firstName} ${lastName}`.trim()
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

    validateFirstName() {
        const input = this.template.querySelector('[data-id="firstNameInput"]');
        const value = (this.firstName || '').trim();
        let message = '';

        if (!value) {
            message = 'First name is required.';
        } else if (!NAME_REGEX.test(value)) {
            message = 'First name cannot contain numbers or special characters.';
        }

        if (input) {
            input.setCustomValidity(message);
            input.reportValidity();
        }

        return message === '';
    }

    validateLastName() {
        const input = this.template.querySelector('[data-id="lastNameInput"]');
        const value = (this.lastName || '').trim();
        let message = '';

        if (!value) {
            message = 'Last name is required.';
        } else if (!NAME_REGEX.test(value)) {
            message = 'Last name cannot contain numbers or special characters.';
        }

        if (input) {
            input.setCustomValidity(message);
            input.reportValidity();
        }

        return message === '';
    }

    validateEmailField() {
        const input = this.template.querySelector('[data-id="emailInput"]');
        const value = (this.email || '').trim();
        let message = '';

        if (!value) {
            message = 'Email is required.';
        } else if (!EMAIL_REGEX.test(value)) {
            message = 'Enter a valid email address (e.g. name@example.com).';
        }

        if (input) {
            input.setCustomValidity(message);
            input.reportValidity();
        }

        return message === '';
    }

    validatePhoneField() {
        const input = this.template.querySelector('[data-id="phoneInput"]');
        const value = (this.phone || '').trim();
        let message = '';

        if (!value) {
            message = 'Mobile number is required.';
        } else if (!/^[0-9]+$/.test(value)) {
            message = 'Mobile number must contain digits only.';
        } else if (!PHONE_REGEX.test(value)) {
            message = 'Enter a valid 10-digit mobile number.';
        }

        if (input) {
            input.setCustomValidity(message);
            input.reportValidity();
        }

        return message === '';
    }

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

    handleCloseSuccess() {
        this.showSuccessScreen = false;
        this.closeModal();
    }
}