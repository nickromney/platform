import { makeStyles } from '@material-ui/core';
import { LogoIcon } from './LogoIcon';

const useStyles = makeStyles({
  root: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 10,
    color: '#ffffff',
    fontSize: 22,
    fontWeight: 700,
    letterSpacing: 0,
  },
  wordmark: {
    lineHeight: 1,
  },
});

export const LogoFull = () => {
  const classes = useStyles();

  return (
    <span className={classes.root}>
      <LogoIcon />
      <span className={classes.wordmark}>Portal</span>
    </span>
  );
};
