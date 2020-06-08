/** $Id: I3MuonGun.h 129524 2015-02-24 18:59:23Z nega $
 * @file
 * @author Jakob van Santen <vansanten@wisc.edu>
 *
 * $Revision: 129524 $
 * $Date: 2015-02-24 11:59:23 -0700 (Tue, 24 Feb 2015) $
 */

#ifndef MUONGUN_I3MUONGUN_H_INCLUDED
#define MUONGUN_I3MUONGUN_H_INCLUDED

#include <icetray/I3PointerTypedefs.h>

#include <boost/function.hpp>
#include <boost/array.hpp>
#include <cubature/cubature.h>

class I3Position;
class I3Direction;
class I3RandomService;

// Commonly-used bits
namespace I3MuonGun {

/** Convert an IceCube z-coordinate [m] to a vertical depth [km] */
double GetDepth(double z);

/** @cond */
namespace detail {
	
template <size_t N> struct multiply;
	
template <>
struct multiply<1> {
	typedef boost::function<double (double)> func_t;
	multiply(func_t f, func_t g) : f_(f), g_(g) {}
	func_t f_, g_;
	typedef double result_type;
	inline double operator()(double x) const { return f_(x)*g_(x); }
};

template <>
struct multiply<2> {
	typedef boost::function<double (double, double)> func_t;
	multiply(func_t f, func_t g) : f_(f), g_(g) {}
	func_t f_, g_;
	typedef double result_type;
	inline double operator()(double x, double y) const { return f_(x, y)*g_(x, y); }
};

template <typename Signature>
struct traits {
	static const size_t arity = boost::function<Signature>::arity;
	typedef boost::array<double, arity> array_type;
};

// These adapters should have been autogenerated, but preprocessor looping is a pain.
template <typename Signature>
inline double
call(boost::function<Signature>* f, const double *x);

template <>
inline double
call(boost::function<double (double, double)> *f, const double *x)
{
	return (*f)(x[0], x[1]);
}

template <>
inline double
call(boost::function<double (double, double, double)> *f, const double *x)
{
	return (*f)(x[0], x[1], x[2]);
}

template <>
inline double
call(boost::function<double (double, double, double, double)> *f, const double *x)
{
	return (*f)(x[0], x[1], x[2], x[3]);
}

template <typename Signature>
void
integrate_thunk(unsigned ndims, const double *x, void *p, unsigned fdims, double *fval)
{
	assert(ndims == traits<Signature>::arity);
	assert(fdims == 1);
	
	fval[0] = call<Signature>(static_cast<boost::function<Signature>* >(p), x);
}

}
/** @endcond */


// 1-dimensional quadtature via GSL QAGS implementation
double Integrate(boost::function<double (double)> f, double low, double high, double epsabs=1.49e-6, double epsrel=1.49e-6, size_t limit=50);

// N-dimensional adaptive cubature
template <typename Signature>
double
Integrate(boost::function<Signature> f, typename detail::traits<Signature>::array_type low, typename detail::traits<Signature>::array_type high,
    double epsabs=1.49e-6, double epsrel=1.49e-6, size_t limit=0)
{
	double result, error;
	unsigned fdims = 1;
	unsigned ndims = detail::traits<Signature>::arity;
	
	// int err =
    adapt_integrate(fdims, &detail::integrate_thunk<Signature>, &f, ndims, &low.front(), &high.front(), limit, epsabs, epsrel, &result, &error);
	
	return result;
}

}

#endif
