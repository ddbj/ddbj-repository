import Component from '@glimmer/component';

type Signature = {
  Args: {
    route: string;
    current: number;
    last: number;
  };
};

export default class PaginationComponent extends Component<Signature> {
  get pages() {
    const { last } = this.args;

    return [...Array(last)].map((_, i) => i + 1);
  }

  get prev() {
    const { current } = this.args;

    return current === 1 ? undefined : current - 1;
  }

  get next() {
    const { current, last } = this.args;

    return current === last ? undefined : current + 1;
  }
}
