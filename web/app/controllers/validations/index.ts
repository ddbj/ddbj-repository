import ValidationsIndexBaseController from 'repository/controllers/validations-index-base';

export const queryParams = [
  {
    page: { type: 'number' } as const,
    db: { type: 'string' } as const,
    created: { type: 'string' } as const,
    progress: { type: 'string' } as const,
    validity: { type: 'string' } as const,
    submitted: { type: 'boolean' } as const,
  },
];

export default class ValidationsIndexController extends ValidationsIndexBaseController {
  queryParams = queryParams;
}
