import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableTimeSlots from '@salesforce/apex/AppointmentControllerToOpp.getAvailableTimeSlots';
import updateAppointmentStatus from '@salesforce/apex/AppointmentControllerToOpp.updateAppointmentStatus';
import { getRecord } from 'lightning/uiRecordApi';
import OPP_APPT_STATUS from '@salesforce/schema/Opportunity.Re_Visit_Site_Appointment_Status__c';

import SITE_URL from '@salesforce/label/c.Arelia_Site_Label';

const ACTION_APPROVE = 'APPROVE';
const ACTION_OPEN_RESCHEDULE = 'OPEN_RESCHEDULE';
const ACTION_SUBMIT_RESCHEDULE = 'SUBMIT_RESCHEDULE';

export default class AppointmentApprovalToOpp extends LightningElement {
    @track showReschedule = false;
    @track showConfirm = false;
    @track showThankYou = false;

    @track confirmTitle = '';
    @track confirmMessage = '';
    pendingAction;

    @track timeSlotOptions = [];
    @track selectedTimeSlot = '';
    @track selectedDate = '';

    @track buttonsDisabled = false;
    @track issubmitting = false; // ✅ lowercase for template safety

    recordId;
    minDate;
    currentStatus;

    get confirmbuttonsdisabled() {
        return this.issubmitting;
    }

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);
        this.recordId = params.get('id');

        const today = new Date();
        const yyyy = today.getFullYear();
        const mm = String(today.getMonth() + 1).padStart(2, '0');
        const dd = String(today.getDate()).padStart(2, '0');
        this.minDate = `${yyyy}-${mm}-${dd}`;
    }

    @wire(getRecord, { recordId: '$recordId', fields: [OPP_APPT_STATUS] })
    wiredOpp({ data, error }) {
        if (data) {
            this.currentStatus = data.fields.Re_Visit_Site_Appointment_Status__c.value;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error(error);
        }
    }

    onApproveClick() {
        if (this.buttonsDisabled) return;
        this.closereschedulepanel();

        this.openconfirm(
            'Confirm Approval',
            'Are you sure you want to approve this site visit appointment?',
            ACTION_APPROVE
        );
    }

    onRescheduleClick() {
        if (this.buttonsDisabled) return;

        if (this.currentStatus === 'Approved') {
            this.showToast('Error', 'This appointment is already approved and cannot be rescheduled.', 'error');
            return;
        }

        this.openconfirm(
            'Confirm Reschedule',
            'Do you want to reschedule this site visit appointment?',
            ACTION_OPEN_RESCHEDULE
        );
    }

    cancelReschedule() {
        this.closereschedulepanel();
    }

    closereschedulepanel() {
        this.showReschedule = false;
        this.selectedDate = '';
        this.selectedTimeSlot = '';
        this.timeSlotOptions = [];
    }

    async handleDateChange(event) {
        this.selectedDate = event.target.value;
        this.selectedTimeSlot = '';
        this.timeSlotOptions = [];

        if (!this.selectedDate || !this.recordId) return;

        try {
            const slots = await getAvailableTimeSlots({
                forDate: this.selectedDate,
                currentOpportunityId: this.recordId
            });
            this.timeSlotOptions = (slots || []).map((s) => ({ label: s, value: s }));
            if (this.timeSlotOptions.length === 0) {
                this.showToast('No Slots', 'No time slots available for the selected date.', 'warning');
            }
        } catch (e) {
            const msg = e?.body?.message || 'Failed to load time slots.';
            this.showToast('Error', msg, 'error');
        }
    }

    handleTimeSlotChange(event) {
        this.selectedTimeSlot = event.detail.value;
    }

    onRescheduleSubmitClick() {
        if (!this.selectedDate || !this.selectedTimeSlot) {
            this.showToast('Missing Input', 'Please select both date and time slot.', 'error');
            return;
        }

        const selected = new Date(this.selectedDate);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        selected.setHours(0, 0, 0, 0);

        if (selected < today) {
            this.showToast('Invalid Date', 'Please select today or a future date.', 'error');
            return;
        }

        const pretty = this.prettyDate(this.selectedDate);
        this.openconfirm(
            'Confirm Reschedule',
            `Are you sure you want to reschedule to ${pretty} at ${this.selectedTimeSlot}?`,
            ACTION_SUBMIT_RESCHEDULE
        );
    }

    openconfirm(title, message, action) {
        this.confirmTitle = title;
        this.confirmMessage = message;
        this.pendingAction = action;
        this.issubmitting = false;
        this.showConfirm = true;
    }

    confirmNo() {
        if (this.issubmitting) return;
        this.showConfirm = false;
        this.pendingAction = null;
        this.issubmitting = false;
    }

    confirmYes() {
        if (this.issubmitting) return;

        this.issubmitting = true;
        this.buttonsDisabled = true;

        if (this.pendingAction === ACTION_OPEN_RESCHEDULE) {
            this.issubmitting = false;
            this.buttonsDisabled = false;
            this.showConfirm = false;
            this.showReschedule = true;
            return;
        }

        if (this.pendingAction === ACTION_APPROVE) {
            this.submit('Approved');
            return;
        }

        if (this.pendingAction === ACTION_SUBMIT_RESCHEDULE) {
            this.submit('Rescheduled', '', this.selectedDate, this.selectedTimeSlot);
            return;
        }

        this.issubmitting = false;
        this.buttonsDisabled = false;
        this.showConfirm = false;
    }

    submit(status, rejectionReason = '', rescheduleDate = null, timeSlot = '') {
        updateAppointmentStatus({
            opportunityId: this.recordId,
            status,
            rejectionReason,
            rescheduleDate,
            timeSlot
        })
            .then(() => {
                this.issubmitting = false;
                this.showConfirm = false;
                this.closereschedulepanel();
                this.showThankYou = true;
                this.currentStatus = status;
            })
            .catch((error) => {
                this.issubmitting = false;
                this.buttonsDisabled = false;
                const msg = error?.body?.message || 'Something went wrong.';
                this.showToast('Error', msg, 'error');
            });
    }

    handleClose() {
        const url = (SITE_URL || '').trim();
        if (url) {
            window.location.assign(url);
        } else {
            this.showThankYou = false;
            this.buttonsDisabled = false;
        }
    }

    prettyDate(yyyyMmDd) {
        try {
            const d = new Date(yyyyMmDd);
            return d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
        } catch (e) {
            return yyyyMmDd;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}