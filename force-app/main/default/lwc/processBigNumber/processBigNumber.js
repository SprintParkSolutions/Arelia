import { LightningElement, api } from 'lwc';
import SITE_BASE_URL from '@salesforce/label/c.Arelia_Site_Label';
import REGISTRATION_FORM_URL from '@salesforce/label/c.Registration_Form_URL';
export default class ProcessBigNumber extends LightningElement {
  @api steps = [
    {
      id: 's1',
      title: 'Inquiry & OTP Verification',
      description:
        'Clients submit the enquiry form and verify their email through OTP to ensure secure communication.'
    },
    {
      id: 's2',
      title: 'Project Request Form',
      description:
        'Clients choose Manual Mode (preset designs) or Smart Auto Mode for a fully customized design experience.'
    },
    {
      id: 's3',
      title: 'Supervisor Site Visit',
      description:
        'Supervisor visits the site, takes measurements, studies land conditions, and understands the requirements.'
    },
    {
      id: 's4',
      title: 'Budget & Estimation',
      description:
        'We calculate project estimate based on materials, site analysis, scope of work, and service requirements.'
    },
    {
      id: 's5',
      title: 'Vendor Tender & Assignment',
      description:
        'We invite vendor quotations, evaluate offers, negotiate, and assign the most suitable vendor.'
    },
    {
      id: 's6',
      title: 'Live Project Tracking',
      description:
        'Clients get daily updates, photos, milestones, and dashboards to track progress from anywhere.'
    }
  ];

  hasObserved = false;
  baseUrl = SITE_BASE_URL;

  get registrationFormUrl() {
    return this.baseUrl + REGISTRATION_FORM_URL;
  }

  get stepsWithIndex() {
    return this.steps.map((s, idx) => {
      return {
        ...s,
        index: idx + 1,
        indexFormatted: (idx + 1).toString().padStart(2, '0')
      };
    });
  }

  renderedCallback() {
    // init observer once
    if (this.hasObserved) return;
    this.hasObserved = true;

    const root = this.template.querySelector('.process-root');
    if (!root) return;

    const io = new IntersectionObserver(
      (entries, observer) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            // trigger the CSS reveal
            root.classList.add('in-view');
            observer.unobserve(entry.target);
          }
        });
      },
      {
        root: null,
        threshold: 0.12
      }
    );

    io.observe(root);
  }

  handleStart() {
    window.location.href = this.registrationFormUrl;
  }
}