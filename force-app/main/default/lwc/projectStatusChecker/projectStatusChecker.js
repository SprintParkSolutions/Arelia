import { LightningElement, track } from 'lwc';
import loginAndFetch from '@salesforce/apex/ProjectStatusController.loginAndFetch';

export default class ProjectStatusChecker extends LightningElement {
    @track email = '';
    @track password = '';

    @track isLoggedIn = false;
    @track isLoading = false;
    @track errorMessage = '';

    @track projects = [];
    @track customer = null;

    // ✅ NEW: selected project
    @track selectedProjectId = null;

    get hasProjects() {
        return this.projects && this.projects.length > 0;
    }

    get hasCustomer() {
        return this.customer != null;
    }

    // ✅ View modes
    get isProjectListView() {
        return this.selectedProjectId == null;
    }

    get isProjectDetailView() {
        return this.selectedProjectId != null;
    }

    get selectedProject() {
        return (this.projects || []).find(p => p.id === this.selectedProjectId) || null;
    }

    // ✅ Summary Counts
    get totalProjects() {
        return (this.projects || []).length;
    }

    get activeProjects() {
        return (this.projects || []).filter(p => p.isActive).length;
    }

    get inactiveProjects() {
        return (this.projects || []).filter(p => !p.isActive).length;
    }

    /* =========================
       LOGIN HANDLERS
    ========================== */

    handleEmailChange(event) {
        this.email = event.target.value;
    }

    handlePasswordChange(event) {
        this.password = event.target.value;
    }

    handleLogout() {
        this.isLoggedIn = false;
        this.projects = [];
        this.customer = null;
        this.selectedProjectId = null;
        this.email = '';
        this.password = '';
        this.errorMessage = '';
        this.isLoading = false;
    }

    async handleLogin() {
        if (!this.email || !this.password) {
            this.errorMessage = 'Please enter both Email and Password.';
            return;
        }

        this.errorMessage = '';
        this.isLoading = true;

        try {
            const result = await loginAndFetch({
                email: this.email,
                password: this.password
            });

            if (!result || !result.success) {
                this.isLoggedIn = false;
                this.projects = [];
                this.customer = null;
                this.selectedProjectId = null;
                this.errorMessage = result ? result.message : 'Unknown error.';
                return;
            }

            this.customer = result.customer || null;

            const rawProjects = result.projects || [];
            this.projects = this.decorateProjects(rawProjects);

            // ✅ Start always on project list screen
            this.selectedProjectId = null;

            this.isLoggedIn = true;
        } catch (e) {
            let msg = 'Unexpected error.';
            if (e && e.body && e.body.message) {
                msg = e.body.message;
            }
            this.errorMessage = msg;
            this.isLoggedIn = false;
            this.projects = [];
            this.customer = null;
            this.selectedProjectId = null;
        } finally {
            this.isLoading = false;
        }
    }

    /* =========================
       SELECT PROJECT
    ========================== */

    handleSelectProject(event) {
        const pid = event.currentTarget.dataset.id;
        this.selectedProjectId = pid;
    }

    handleBackToProjects() {
        this.selectedProjectId = null;
    }

    /* =========================
       ACTIVE/INACTIVE BY Project__c.Status__c
       Active = Initiated, In Progress, Hold
       Inactive = Completed, Cancelled
    ========================== */

    isProjectActive(status) {
        const s = (status || '').trim();
        const inactiveStatuses = new Set(['Completed', 'Cancelled']);
        return !inactiveStatuses.has(s);
    }

    /* =========================
       DECORATE DATA FOR UI
    ========================== */

    decorateProjects(rawProjects) {
        return (rawProjects || []).map((p, projIndex) => {
            const vendors = (p.vendorAssignments || []).map((va, vaIndex) => {
                const progressPercent = this.normalizePercent(va.completionPercent);
                const circleStyle = this.buildCircleStyle(progressPercent);

                const tasks = va.tasks || [];
                let finalCompletionDate = null;
                tasks.forEach((t) => {
                    if (t.finalCompletedDate) {
                        if (!finalCompletionDate || t.finalCompletedDate > finalCompletionDate) {
                            finalCompletionDate = t.finalCompletedDate;
                        }
                    }
                });

                // open FIRST vendor of FIRST project by default (only matters in detail view)
                const isFirstVendor = projIndex === 0 && vaIndex === 0;

                return {
                    ...va,
                    progressPercent,
                    circleStyle,
                    finalCompletionDate,
                    expanded: isFirstVendor,
                    tasksClass: isFirstVendor ? 'vaTasks vaTasks-open' : 'vaTasks vaTasks-closed',
                    chevronClass: isFirstVendor ? 'chevron chevron-open' : 'chevron'
                };
            });

            const projectProgress = this.normalizePercent(p.completionPercent);
            const projectCircleStyle = this.buildCircleStyle(projectProgress);
            const isActive = this.isProjectActive(p.status);

            // ✅ List-card styles
            const badgeClass = isActive ? 'listBadge listBadge-active' : 'listBadge listBadge-inactive';
            const listCardClass = isActive ? 'projListCard' : 'projListCard projListCard-inactive';

            return {
                ...p,
                isActive,
                vendorAssignments: vendors,
                progressPercent: projectProgress,
                circleStyle: projectCircleStyle,
                badgeClass,
                listCardClass
            };
        });
    }

    normalizePercent(value) {
        let num = value == null ? 0 : Number(value);
        if (isNaN(num)) num = 0;
        if (num < 0) num = 0;
        if (num > 100) num = 100;
        return Math.round(num * 100) / 100;
    }

    buildCircleStyle(percent) {
        const p = percent || 0;
        return `--p:${p};`;
    }

    /* =========================
       VENDOR COLLAPSE
    ========================== */

    toggleVendor(event) {
        const vid = event.currentTarget.dataset.id;

        this.projects = this.projects.map((p) => {
            const updatedVendors = (p.vendorAssignments || []).map((va) => {
                if (va.id === vid) {
                    const expanded = !va.expanded;
                    return {
                        ...va,
                        expanded,
                        tasksClass: expanded ? 'vaTasks vaTasks-open' : 'vaTasks vaTasks-closed',
                        chevronClass: expanded ? 'chevron chevron-open' : 'chevron'
                    };
                }
                return va;
            });

            return { ...p, vendorAssignments: updatedVendors };
        });
    }
}