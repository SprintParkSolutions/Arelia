import { LightningElement, api, wire, track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import scheduleAppointmentAndSendEmails from '@salesforce/apex/ScheduleAppointmentController.scheduleAppointmentAndSendEmails';
import getAvailableTimeSlots from '@salesforce/apex/AppointmentController.getAvailableTimeSlots';
import getAppointmentTypesPicklistValues from '@salesforce/apex/ScheduleAppointmentController.getAppointmentTypesPicklistValues';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

// ✅ Added appointment fields to verify if data already exists
const FIELDS = [
    'Lead.Id', 
    'Lead.Supervisor_User__c', 
    'Lead.Appointment_Date__c', 
    'Lead.Appointment_Status__c'
];

export default class ScheduleAppointment extends LightningElement {
    @api recordId; // Lead Id from page
    leadId;
    supervisorId;
    appointmentDate;
    appointmentTime;
    
    // Track if Lead has prior appointment data saved
    hasPreviousAppointment = false;
    allAppointmentTypes = [];

    @track timeSlotOptions = [];
    @track selectedTimeSlot = '';

    @track appointmentTypeOptions = [];
    @track selectedAppointmentType = '';

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredLead({ error, data }) {
        if (data) {
            this.leadId = data.fields.Id.value;
            this.supervisorId = data.fields.Supervisor_User__c?.value;
            
            // ✅ Check if there is already appointment data populated on the record
            const hasDate = !!data.fields.Appointment_Date__c?.value;
            const statusValue = data.fields.Appointment_Status__c?.value;
            
            // Treat as a previous appointment ONLY if a date exists OR the status is something other than 'Pending'
            const hasValidStatus = statusValue && statusValue.toLowerCase() !== 'pending';
            
            this.hasPreviousAppointment = hasDate || hasValidStatus;

            // Attempt to filter types now that we have lead data
            this.filterAppointmentTypes();

            // If user picked a date before record wire resolved, load slots now
            if (this.appointmentDate) {
                this.loadAvailableSlots();
            }
        } else if (error) {
            this.showToast('Error', 'Failed to load Lead or Supervisor data.', 'error');
        }
    }

    connectedCallback() {
        // Load appointment types once
        getAppointmentTypesPicklistValues()
            .then(list => {
                this.allAppointmentTypes = (list || []).map(v => ({ label: v, value: v }));
                this.filterAppointmentTypes();
            })
            .catch(err => {
                const msg = err?.body?.message || 'Failed to load appointment types.';
                this.showToast('Error', msg, 'error');
            });
    }

    // Filters the dropdown based on first-time or follow-up status
    filterAppointmentTypes() {
        // Ensure both picklist values and lead data are loaded
        if (!this.allAppointmentTypes.length || !this.leadId) {
            return;
        }

        if (this.hasPreviousAppointment) {
            // Data exists -> Second time onwards -> Only show Follow Up
            this.appointmentTypeOptions = this.allAppointmentTypes.filter(opt => 
                opt.value.toLowerCase().includes('follow')
            );
        } else {
            // Data is null/empty (or just 'Pending') -> First time -> Only show New
            this.appointmentTypeOptions = this.allAppointmentTypes.filter(opt => 
                opt.value.toLowerCase() === 'new'
            );
        }

        // Auto-select the only available option to save the user a click
        if (this.appointmentTypeOptions.length === 1) {
            this.selectedAppointmentType = this.appointmentTypeOptions[0].value;
        }
    }

    handleDateChange(event) {
        this.appointmentDate = event.target.value;
        this.selectedTimeSlot = '';
        this.loadAvailableSlots();
    }

    handleTimeChange(event) {
        this.appointmentTime = event.target.value;
    }

    handleTimeSlotChange(event) {
        this.selectedTimeSlot = event.detail.value;
    }

    handleAppointmentTypeChange(event) {
        this.selectedAppointmentType = event.detail.value;
    }

    get todayDate() {
        const today = new Date();
        return today.toISOString().split('T')[0]; // yyyy-mm-dd
    }

    loadAvailableSlots() {
        // Need both date and lead to scope availability
        if (!this.appointmentDate || !this.leadId) {
            this.timeSlotOptions = [];
            return;
        }
        getAvailableTimeSlots({ forDate: this.appointmentDate, currentLeadId: this.leadId })
            .then((slots) => {
                this.timeSlotOptions = (slots || []).map(s => ({ label: s, value: s }));
                if (!this.timeSlotOptions.length) {
                    this.showToast('No Slots', 'No time slots are available for the selected date.', 'warning');
                }
            })
            .catch((error) => {
                const msg = error?.body?.message || 'Failed to load available slots.';
                this.showToast('Error', msg, 'error');
                this.timeSlotOptions = [];
            });
    }

    handleSchedule() {
        if (!this.appointmentDate || !this.selectedTimeSlot || !this.selectedAppointmentType) {
            this.showToast('Missing Input', 'Please select appointment type, date, and time slot.', 'warning');
            return;
        }

        if (!this.leadId || !this.supervisorId) {
            this.showToast('Missing Input', 'Lead or Supervisor information is not available.', 'error');
            return;
        }

        // Validate the selected slot is not in the past for today
        if (this.appointmentDate === this.todayDate) {
            const now = new Date();
            const startTimeRaw = this.selectedTimeSlot.split('-')[0].trim(); // e.g., "9 AM" or "9:30 AM"

            const timeParts = startTimeRaw.match(/(\d+)(?::(\d+))?\s*(AM|PM)/i);
            if (timeParts) {
                let hour = parseInt(timeParts[1], 10);
                const minute = parseInt(timeParts[2] || '0', 10);
                const ampm = timeParts[3].toUpperCase();

                if (ampm === 'PM' && hour !== 12) hour += 12;
                if (ampm === 'AM' && hour === 12) hour = 0;

                const slotDateTime = new Date();
                slotDateTime.setHours(hour, minute, 0, 0);

                if (slotDateTime <= now) {
                    this.showToast('Invalid Time Slot', 'Selected time slot has already passed for today.', 'error');
                    return;
                }
            } else {
                this.showToast('Invalid Time Slot', 'Unable to parse selected time slot format.', 'error');
                return;
            }
        }

        scheduleAppointmentAndSendEmails({
            leadId: this.leadId,
            supervisorId: this.supervisorId,
            appointmentDate: this.appointmentDate,
            timeSlot: this.selectedTimeSlot,
            appointmentType: this.selectedAppointmentType 
        })
            .then(() => {
                this.showToast('Success', 'Appointment scheduled successfully.', 'success');
                this.closeQuickAction();
            })
            .catch(error => {
                const message = error?.body?.message || 'Error sending appointment emails.';
                this.showToast('Error', message, 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    
    closeQuickAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}